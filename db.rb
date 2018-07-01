require "active_record"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "db/db.sqlite3"
)

class User < ActiveRecord::Base
end

class Comment < ActiveRecord::Base
  has_one :user, as: :owner
  has_one :user, as: :reply_to_user
  before_save :update_creation_date

  def update_creation_date
    self.creation_date = Time.at(self.se_creation_date.to_i).to_datetime
  end
end

class Regex < ActiveRecord::Base
  belongs_to :reason
end

class Reason < ActiveRecord::Base
  has_many :regexes
end

class Room < ActiveRecord::Base
end

class WhitelistedUser < ActiveRecord::Base
end
