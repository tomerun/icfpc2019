require "random"
require "./defs"

class Solver
  def initialize(@map : Map, @tl : Int64)
  end

  def solve
    score = 42
    @map.bots << Bot.new(Point.new(5, 7))
    @map.bots[0].actions << ActionSimple::W << ActionSimple::S << ActionB.new(-1, 2)
    @map.bots[1].actions << ActionX.new(9, 8) << ActionSimple::C
    commands = @map.bots.map { |bot| bot.actions.join }
    {score, commands}
    # returns {score, Array(Array(ActionType))}
  end
end
