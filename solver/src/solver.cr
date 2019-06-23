require "random"
require "./defs"

class Solver
  @map : Map

  def initialize(@orig_map : Map, @tl : Int64)
    @map = @orig_map.clone
  end

  def solve : Tuple(Int32, Array(Array(ActionType)))
    max_elapse = 0i64
    prev_time = Time.now.to_unix_ms
    res = {Int32::MAX, [] of Array(ActionType)}
    while prev_time + max_elapse < @tl
      score, commands = solve_single
      if score < res[0]
        res = {score, commands}
      end
      cur_time = Time.now.to_unix_ms
      STDERR.puts("time:#{cur_time - prev_time} score:#{score}")
      max_elapse = {max_elapse, cur_time - prev_time}.max
      prev_time = cur_time
    end
    res
  end

  private def solve_single : Tuple(Int32, Array(Array(ActionType)))
    @map = @orig_map.clone
    time = 0
    next_spawn = [] of Bot
    while @map.n_empty > 0
      time += 1
      @map.bots.each do |bot|
        @map.get_booster(bot)
        action = select_action(bot, @map)
        @map.apply_action(action, bot, next_spawn)
      end
      @map.finalize_turn(next_spawn)
    end
    commands = @map.bots.map { |bot| bot.actions }
    {time, commands}
  end

  private def select_action(bot, map)
    return ActionSimple::Z if map.n_empty == 0

    if map.n_B > 0
    elsif map.n_F > 0 && bot.fast_time == 0
    else
    end
    ActionSimple::Z
  end
end
