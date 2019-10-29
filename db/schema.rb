# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2019_10_29_122626) do

  create_table "chat_users", force: :cascade do |t|
    t.text "name"
    t.bigint "user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body"
    t.text "body_markdown"
    t.integer "comment_id"
    t.text "se_creation_date"
    t.boolean "edited"
    t.text "link"
    t.integer "owner_id"
    t.integer "post_id"
    t.text "post_type"
    t.integer "reply_to_user"
    t.integer "score"
    t.integer "tps"
    t.integer "fps"
    t.integer "rude"
    t.datetime "creation_date"
    t.decimal "perspective_score", precision: 15, scale: 10
  end

  create_table "feedback_typedefs", force: :cascade do |t|
    t.text "feedback"
  end

  create_table "feedbacks", force: :cascade do |t|
    t.integer "feedback_type_id"
    t.integer "comment_id"
    t.bigint "chat_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "reasons", force: :cascade do |t|
    t.text "name"
    t.text "description"
  end

  create_table "regexes", force: :cascade do |t|
    t.text "post_type"
    t.text "regex"
    t.integer "reason_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.integer "room_id"
    t.boolean "magic_comment"
    t.boolean "regex_match"
    t.boolean "on"
  end

  create_table "users", force: :cascade do |t|
    t.integer "accept_rate"
    t.text "display_name"
    t.text "link"
    t.text "profile_image"
    t.integer "reputation"
    t.integer "user_id"
    t.text "user_type"
  end

  create_table "whitelisted_users", force: :cascade do |t|
    t.bigint "user_id"
  end

end
