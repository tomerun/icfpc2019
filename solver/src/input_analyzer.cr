require "mysql"
require "./defs"

def analyze(filename)
  STDERR << filename << "\n"
  taskname = /\/([^\/]+).desc\Z/.match(filename).not_nil![1]
  map = InputParser.parse(File.read("../data/" + filename))
  empty_cell = map.wall.map { |row| row.count(false) }.sum
  bc = map.booster.values.group_by { |b| b }.transform_values { |v| v.size }
  DB.open "mysql://#{ENV["DB_USER"]}:#{ENV["DB_PASS"]}@#{ENV["DB_DOMAIN"]}/icfpc" do |db|
    db.exec(
      "insert into tasks values (#{(['?'] * 10).join(",")})",
      taskname, map.h, map.w, empty_cell,
      bc.fetch(BoosterType::B, 0), bc.fetch(BoosterType::F, 0), bc.fetch(BoosterType::L, 0),
      bc.fetch(BoosterType::X, 0), bc.fetch(BoosterType::R, 0), bc.fetch(BoosterType::C, 0)
    )
  end
end

tasks = [
  "part-1-examples/example-01.desc",
  "part-2-teleports-examples/example-02.desc",
  "part-3-clones-examples/example-03.desc",
]
1.upto(150) { |i| tasks << "part-1-initial/prob-#{sprintf("%03d", i)}.desc" }
151.upto(220) { |i| tasks << "part-2-teleports/prob-#{sprintf("%03d", i)}.desc" }
221.upto(300) { |i| tasks << "part-3-clones/prob-#{sprintf("%03d", i)}.desc" }

tasks.each { |t| analyze(t) }
