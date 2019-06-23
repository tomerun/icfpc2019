require "random"
require "./defs"

class Solver
  @@WRAP_SCORE = 10000.0
  @@NEAR_SCORE = 1000.0
  @map : Map
  @bbuf
  @apbuf

  def initialize(@orig_map : Map, @tl : Int64)
    @map = @orig_map.clone
    @rnd = Random.new(42)
    @bbuf = BFSBuffer.new
    @apbuf = [] of Point
  end

  def solve : Tuple(Int32, Array(Array(ActionType)))
    @bbuf.init(@map.h, @map.w)
    res = {Int32::MAX, [] of Array(ActionType)}
    max_elapse = 0i64
    prev_time = Time.now.to_unix_ms
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
      select_arm(bot, map)
    elsif map.n_F > 0 && bot.fast_time == 0
      ActionSimple::F
    else
      evals = {
        evalute_W(bot, map),
        evalute_S(bot, map),
        evalute_A(bot, map),
        evalute_D(bot, map),
        evalute_E(bot, map),
        evalute_Q(bot, map),
      }
    end
    ActionSimple::Z
  end

  private def evalute_W(bot, map)
    {ActionSimple::W, evaluate_move(bot, map, 0, 1)}
  end

  private def evalute_W(bot, map)
    {ActionSimple::S, evaluate_move(bot, map, 0, -1)}
  end

  private def evalute_A(bot, map)
    {ActionSimple::A, evaluate_move(bot, map, -1, 0)}
  end

  private def evalute_D(bot, map)
    {ActionSimple::D, evaluate_move(bot, map, 1, 0)}
  end

  private def evalute_move(bot, map, dx, dy)
    nx = bot.x + dx
    ny = bot.y + dy
    return 0.0 if !map.inside(nx, ny) || map.wall[ny][nx]
    if bot.fast_time > 0 &&
       map.inside(nx + dx, ny + dy) &&
       !map.wall[ny + dx][nx + dy]
      evaluate_move2(bot, map, dx, dy)
    else
    end
  end

  private def evalute_move2(bot, map, dx, dy)
    nx = bot.x + dx
    ny = bot.y + dy
    wrapped = [] of Point
    begin
      bot.arm.each do |p|
        if map.inside(nx + p.x, ny + p.y) &&
           !map.wrapped[ny + p.y][nx + p.x] &&
           map.visible(nx, ny, p.x, p.y)
          map.wrapped[ny + p.y][nx + p.x] = true
          wrapped << Point.new(nx + p.x, ny + p.y)
        end
      end
      if !map.wrapped[ny][nx]
        map.wrapped[ny][nx] = true
        wrapped << Point.new(nx, ny)
      end
      nx += dx
      ny += dy
      bot.arm.each do |p|
        if map.inside(nx + p.x, ny + p.y) &&
           !map.wrapped[ny + p.y][nx + p.x] &&
           map.visible(nx, ny, p.x, p.y)
          map.wrapped[ny + p.y][nx + p.x] = true
          wrapped << Point.new(nx + p.x, ny + p.y)
        end
      end
      if !map.wrapped[ny][nx]
        map.wrapped[ny][nx] = true
        wrapped << Point.new(nx, ny)
      end
      return @@WRAP_SCORE * wrapped.size * 100 if map.n_empty == wrapped.size

      score = @@WRAP_SCORE * wrapped.size
      dist = distance(bot, map)
      score
    ensure
      wrapped.each do |p|
        map.wrapped[p.y][p.x] = false
      end
    end
  end

  private def distance(bot, map)
    @bbuf.gen += 1
    @bbuf.set(nx, ny)
    @apbuf.clear
    @apbuf << Point.new(nx, ny)
  end

  private def evalute_E(bot, map)
  end

  private def evalute_Q(bot, map)
  end

  private def select_arm(bot, map)
    s = Set(Point).new
    s << Point.new(bot.x, bot.y + 1)
    s << Point.new(bot.x, bot.y - 1)
    s << Point.new(bot.x + 1, bot.y)
    s << Point.new(bot.x - 1, bot.y)
    bot.arm.each do |p|
      s << Point.new(p.x, p.y + 1)
      s << Point.new(p.x, p.y - 1)
      s << Point.new(p.x + 1, p.y)
      s << Point.new(p.x - 1, p.y)
    end
    s.delete(bot.pos)
    bot.arm.each do |p|
      s.delete(p)
    end
    a = Array(Point).new
    s.each do |p|
      {p.x.abs, p.y.abs}.times { a << p }
    end
    ap = a.sample(@rnd)
    ActionB.new(ap.x, ap.y)
  end
end

class BFSBuffer
  property idx, gen

  def initialize
    @idx = Array(Array(Int32)).new
    @gen = 0
  end

  def init(h, w)
    @idx = Array.new(h) { Array(Int32).new(w, 0) }
    @gen = 0
  end

  def set(x, y)
    @idx[y][x] = @gen
  end

  def get(x, y)
    @idx[y][x] == @gen
  end
end

struct ActionEval
  getter act, score

  def initialize(@act : ActionType, @score : Float64)
  end
end
