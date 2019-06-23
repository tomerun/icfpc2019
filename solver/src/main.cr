require "json"
require "mysql"
require "random"
require "./defs"
require "./solver"

class Result
  property task, score, commands

  def initialize(@task : String, @score : Int32, @commands : String)
  end

  def upload
    options = Hash(String, JSON::Any::Type).new
    options["TIMELIMIT"] = ENV["TIMELIMIT"].to_i64
    DB.open "mysql://#{ENV["DB_USER"]}:#{ENV["DB_PASS"]}@#{ENV["DB_DOMAIN"]}/icfpc" do |db|
      db.exec(
        "insert into results(task, created_at, tag, score, commands, options) values (?, ?, ?, ?, ?, ?)",
        @task, Time.now, ENV["TAG"], @score, @commands, options.to_json)
    end
  end
end

start_time = Time.now.to_unix_ms
map = InputParser.parse(read_line)
solver = Solver.new(map, start_time + ENV["TIMELIMIT"].to_i64)
score, commands = solver.solve
cmd_str = [] of String
commands.each do |cs|
  cmd_str << cs.join
end
res = Result.new(ENV["TASKNAME"], score, cmd_str.join("#"))
# res = Result.new(ENV["TASKNAME"], score, commands.map { |cs| cs.join }.join("#"))
puts res.commands
# res.upload
