require "json"
require "mysql"
require "random"
require "./input_parser"

class Result
  property task, score, commands

  def initialize(@task : String, @score : Int32, @commands : String)
  end

  def upload
    options = Hash(String, JSON::Any::Type).new
    options["TIMELIMIT"] = ENV["TIMELIMIT"].to_i64
    DB.open "mysql://#{ENV["DB_USER"]}:#{ENV["DB_PASS"]}@#{ENV["DB_DOMAIN"]}/icfpc" do |db|
      db.exec(
        "insert into results(task, created_at, score, commands, options) values (?, ?, ?, ?, ?)",
        @task, Time.now, @score, @commands, options.to_json)
    end
  end
end

puts InputParser.parse(read_line)
# res = Result.new(ENV["TASKNAME"], Random.rand(1000), "AEIOU")
# res.upload
