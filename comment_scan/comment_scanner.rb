require './db'
require_relative 'helpers'
require_relative 'message_collection'

class CommentScanner
    attr_reader :seclient, :chatter

    def initialize(seclient, chatter, post_all_comments, ignore_users, perspective_key: '', perspective_log: Logger.new('/dev/null'))
        @seclient = seclient
        @chatter = chatter
        @post_all_comments = post_all_comments
        @ignore_users = ignore_users
        @perspective_key = perspective_key
        @perspective_log = perspective_log

        @latest_comment_date = @seclient.latest_comment_date.to_i+1 unless @seclient.latest_comment_date.nil?
    end

    def scan_new_comments
        new_comments = @seclient.comments_after_date(@latest_comment_date)
        @latest_comment_date = new_comments[0].json["creation_date"].to_i+1 if new_comments.any? && !new_comments[0].nil?
        scan_se_comments([new_comments])
    end

    #def scan_comment(comment_id, should_post_matches: true)
    #    #Does the work of 
    #    comment = seclient.comment_with_id(comment_id)
    #    return false if comment == nil #Didn't actually scan
    #
    #    report_comment(comment, should_post_matches: should_post_matches)
    #end

    def scan_comments_from_db(*comment_ids)
        comment_ids.flatten.each { |comment_id| scan_comment_from_db(comment_id) }
    end

    def scan_comment_from_db(comment_id)
        dbcomment = Comment.find_by(comment_id: comment_id)
        puts "Found #{dbcomment} for #{comment_id}"

        if dbcomment.nil?
            @chatter.say("**BAD ID:** No comment exists in the database for id: #{comment_id}")
            return
        end

        report_db_comments(dbcomment, should_post_matches: false)
    end

    def scan_comments(*comment_ids)
        comment_ids.flatten.each do |comment_id|
            comment = seclient.comment_with_id(comment_id)
            next if comment.nil? #Didn't actually scan

            scan_se_comment(comment)#, should_post_matches)
        end
    end

    def scan_se_comments(comments)
        comments.flatten.each { |comment| scan_se_comment(comment) }
    end

    def scan_se_comment(comment)
        body = comment.body_markdown
        toxicity = perspective_scan(body).to_f

        if dbcomment = record_comment(comment, perspective_score: toxicity)
            report_db_comments(dbcomment, should_post_matches: true)
        end
    end

    def scan_last_n_comments(num_comments)
        return if num_comments.to_i < 1
        comments_to_scan = @seclient.comments[0..(num_comments.to_i - 1)]
        scan_se_comments(comments_to_scan)
    end

    def report_db_comments(*comments, should_post_matches: true)
        comments.flatten.each { |comment| report_db_comment(comment, should_post_matches: should_post_matches) }
    end

    def report_db_comment(comment, should_post_matches: true)
        user = User.where(id: comment["owner_id"])
        user = user.any? ? user.first : false # if user was deleted, set it to false for easy checking

        puts "Grab metadata..."

        author = user ? user.display_name : "(removed)"
        author_link = user ? "[#{author}](#{user.link})" : "(removed)"
        rep = user ? "#{user.reputation} rep" : "(removed) rep"

        #ts = ts_for(comment["creation_date"]

        puts "Grab post data/build message to post..."

        msg = "##{comment["post_id"]} #{author_link} (#{rep})"

        puts "Analyzing post..."

        post_inactive = false # Default to false in case we can't access post
        post = [] # so that we can use this later for whitelisted users

        if post = @seclient.post_exists?(comment["post_id"]) # If post wasn't deleted, do full print
            author = user_for post.owner
            editor = user_for post.last_editor
            creation_ts = ts_for post.json["creation_date"]
            edit_ts = ts_for post.json["last_edit_date"]
            type = post.type[0].upcase
            closed = post.json["close_date"]

            post_inactive = timestamp_to_date(post.json["last_activity_date"]) < timestamp_to_date(comment["creation_date"]) - 30

            msg += " | [#{type}: #{post.title}](#{post.link}) #{'[c]' if closed} (score: #{post.score}) | posted #{creation_ts} by #{author}"
            msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
        end

        # toxicity = perspective_scan(body, perspective_key: settings['perspective_key']).to_f
        toxicity = comment["perspective_score"].to_f

        puts "Building message..."
        msg += " | Toxicity #{toxicity}"
        # msg += " | Has magic comment" if !post_exists?(cli, comment["post_id"]) and has_magic_comment? comment, post
        msg += " | High toxicity" if toxicity >= 0.7
        msg += " | Comment on inactive post" if post_inactive
        msg += " | tps/fps: #{comment["tps"].to_i}/#{comment["fps"].to_i}"

        puts "Building comment body..."

        # If the comment exists, we can just post the link and ChatX will do the rest
        # Else, make a quote manually with just the body (no need to be fancy, this must be old)
        # (include a newline in the manual string to lift 500 character limit in chat)
        # TODO: Chat API is truncating to 500 characters right now even though we're good to post more. Fix this.
        comment_text_to_post = @seclient.comment_deleted?(comment["comment_id"]) ? ("\n> " + comment["body"]) : comment["link"]

        puts "Check reasons..."

        report_text = report(comment["post_type"], comment["body_markdown"])
        reasons = report_raw(comment["post_type"], comment["body_markdown"]).map(&:reason)

        if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
            comment_text_to_post = "⚠️☢️\u{1F6A8} [Offensive/Abusive Comment](#{comment["link"]}) \u{1F6A8}☢️⚠️"
        end

        msgs = MessageCollection::ALL_ROOMS

        puts "Post chat message..."

        if @post_all_comments
            msgs.push comment, @chatter.say(comment_text_to_post)
            msgs.push comment, @chatter.say(msg)
            msgs.push comment, @chatter.say(report_text) if report_text
        elsif !@post_all_comments && (report_text) && (post && !@ignore_users.map(&:to_i).push(post.owner.id).flatten.include?(user.user_id.to_i))
            msgs.push comment, @chatter.say(comment_text_to_post)
            msgs.push comment, @chatter.say(msg)
            msgs.push comment, @chatter.say(report_text) if report_text
        end

        @chatter.rooms.flatten.each do |room_id|
            room = Room.find_by(room_id: room_id)
            next unless (!room.nil? && room.on)

            should_post_message = (
                                    # (room.magic_comment && has_magic_comment?(comment, post)) ||
                                    (room.regex_match && report_text) ||
                                    toxicity >= 0.7 || # I should add a room property for this
                                    post_inactive # And this
                                  ) && should_post_matches && user &&
                                  post && !@ignore_users.map(&:to_i).push(post.owner.id).map(&:to_i).include?(user["user_id"].to_i) &&
                                  (user['user_type'] != 'moderator')

            if should_post_message
                msgs.push comment, @chatter.say(comment_text_to_post, room_id)
                msgs.push comment, @chatter.say(msg, room_id)
                msgs.push comment, @chatter.say(report_text, room_id) if room.regex_match && report_text
            end
        end
    end

    def perspective_scan(text)
        return 'NoKey' unless @perspecitve_key

        puts "Perspective scan..."
        response = HTTParty.post("https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze?key=#{@perspective_key}",
        :body => {
            "comment" => {
                text: text,
                type: 'PLAIN_TEXT' # This should eventually be HTML, when perspective supports it
            },
            "context" => {}, # Not yet supported
            "requestedAttributes" => {
                'TOXICITY' => {
                    scoreType: 'PROBABILITY',
                    scoreThreshold: 0
                }
            },
            "languages" => ["en"],
            "doNotStore" => true,
            "sessionId" => '' # Use this if there are multiple bots running
        }.to_json,
        :headers => { 'Content-Type' => 'application/json' } )

        @perspective_log.info response
        @perspective_log.info response.dig("attributeScores")
        @perspective_log.info response.dig("attributeScores", "TOXICITY")
        @perspective_log.info response.dig("attributeScores", "TOXICITY", "summaryScore")
        @perspective_log.info response.dig("attributeScores", "TOXICITY", "summaryScore", "value")

        response.dig("attributeScores", "TOXICITY", "summaryScore", "value")
    end

end
