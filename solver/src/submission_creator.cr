require "mysql"
require "zip"

DB.open "mysql://#{ENV["DB_USER"]}:#{ENV["DB_PASS"]}@#{ENV["DB_DOMAIN"]}/icfpc" do |db|
  File.open("submit.zip", "w") do |file|
    Zip::Writer.open(file) do |zip|
      db.query(
        "SELECT task, commands FROM results
         WHERE NOT EXISTS (SELECT 1 FROM results sub
         WHERE results.task = sub.task AND
           (results.score > sub.score
             OR (results.score = sub.score AND results.created_at > sub.created_at)
           )
         )
         ORDER BY task;"
      ) do |rs|
        rs.each do
          task = rs.read(String)
          commands = rs.read(String)
          zip.add("#{task}.sol", commands)
        end
      end
    end
  end
end
