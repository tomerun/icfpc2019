require "json"
require "mysql"

# puts read_line.split(";")
# puts ENV["TIMELIMIT"]

struct Result
  property task, score, commands

  def initialize(@task : String, @score : Int32, @commands : String)
  end
end

def upload_result(res : Result)
  options = Hash(String, JSON::Any::Type).new
  options["TIMELIMIT"] = ENV["TIMELIMIT"].to_i64
  DB.open "mysql://#{ENV["DB_USER"]}:#{ENV["DB_PASS"]}@#{ENV["DB_DOMAIN"]}/icfpc" do |db|
    db.exec(
      "insert into results(task, created_at, score, commands, options) values (?, ?, ?, ?, ?)",
      res.task, Time.now, res.score, res.commands, options.to_json)
  end
end

upload_result(Result.new("prob-151", 999, "AEIOU"))
