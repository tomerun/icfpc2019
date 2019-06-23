require "random"
require "./defs"

class Solver
  @@WRAP_SCORE = 10000.0
  @@NEAR_SCORE = 1000.0
  @map : Map

  def initialize(@orig_map : Map, @tl : Int64)
    @map = @orig_map.clone
    @rnd = Random.new(42)
    @bbuf = BFSBuffer.new
    @apbuf = [] of Point
    @simulate_types = [] of Array(ActionType)
    initialize_simulate_types
  end

  def initialize_simulate_types
    # @simulate_types << {ActionSimple::W, ActionSimple::W, ActionSimple::W}
    types = {ActionSimple::W, ActionSimple::S, ActionSimple::A, ActionSimple::D, ActionSimple::E, ActionSimple::Q}
    actions = Array.new(3, ActionSimple::Z)
    initialize_simulate_types_rec(actions, 0, types)
  end

  def initialize_simulate_types_rec(cur, depth, types)
    if depth == cur.size
      @simulate_types << cur.dup
      return
    end
    types.each do |t|
      if depth > 0
        next if t == ActionSimple::W && cur[depth - 1] == ActionSimple::S
        next if t == ActionSimple::S && cur[depth - 1] == ActionSimple::W
        next if t == ActionSimple::A && cur[depth - 1] == ActionSimple::D
        next if t == ActionSimple::D && cur[depth - 1] == ActionSimple::A
        next if t == ActionSimple::Q && cur[depth - 1] == ActionSimple::E
        next if t == ActionSimple::E && cur[depth - 1] == ActionSimple::Q
      end
      cur[depth] = t
      initialize_simulate_types_rec(cur, depth + 1, types)
    end
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
    @map.wrapped[3][0] = true
    time = 0
    next_spawn = [] of Bot
    puts @map.bots[0]
    while @map.n_empty > 10
      time += 1
      @map.bots.each do |bot|
        @map.get_booster(bot)
        action = select_action(bot, @map)
        @map.apply_action(action, bot, next_spawn)
        puts action
        puts bot
      end
      puts @map.n_empty
      @map.finalize_turn(next_spawn)
    end
    commands = @map.bots.map { |bot| bot.actions }
    {time, commands}
  end

  private def select_action(bot, map) : ActionType
    return ActionSimple::Z if map.n_empty == 0
    if map.n_B > 0
      bot.plan.clear
      return select_arm(bot, map)
      # elsif map.n_F > 0 && bot.fast_time == 0
      #   ActionSimple::F
    elsif bot.plan.size >= 3
      return bot.plan.pop
    else
      cur_wrapped = bot.plan.empty? ? 0 : simulate(bot, map, bot.plan.reverse)
      max_wrapped = 0
      max_actions = [] of ActionType
      @simulate_types.each do |actions|
        n = simulate(bot, map, actions)
        if n > max_wrapped
          max_wrapped = n
          max_actions = actions
          puts "#{n} #{max_actions}"
        end
      end
      if max_wrapped > cur_wrapped
        puts "max_wrapped:#{max_wrapped} #{max_actions}"
        bot.plan << max_actions[2] << max_actions[1]
        return max_actions[0]
      end
      if bot.plan.empty?
        create_plan(bot, map)
      end
      return bot.plan.pop if !bot.plan.empty?
    end
    return ActionSimple::Z
  end

  private def simulate(bot, map, actions)
    orig_pos = bot.pos
    orig_arm = bot.arm
    wrapped = [] of Point
    begin
      actions.each do |action|
        case action
        when ActionSimple::W
          bot.y += 1
        when ActionSimple::S
          bot.y -= 1
        when ActionSimple::A
          bot.x -= 1
        when ActionSimple::D
          bot.x += 1
        when ActionSimple::E
          bot.rot_cw
        when ActionSimple::Q
          bot.rot_ccw
        end
        if !map.inside(bot.x, bot.y) || map.wall[bot.y][bot.x]
          return 0
        end
        collect_wrapped(bot, map, wrapped)
      end
      wrapped.size
    ensure
      wrapped.each do |p|
        map.wrapped[p.y][p.x] = false
      end
      bot.pos = orig_pos
      bot.arm = orig_arm
    end
  end

  private def collect_wrapped(bot, map, wrapped)
    bot.arm.each do |ap|
      x = bot.x + ap.x
      y = bot.y + ap.y
      if map.inside(x, y) && !map.wrapped[y][x] && map.visible(bot.x, bot.y, ap.x, ap.y)
        map.wrapped[y][x] = true
        wrapped << Point.new(x, y)
      end
    end
    if !map.wrapped[bot.y][bot.x]
      map.wrapped[bot.y][bot.x] = true
      wrapped << bot.pos
    end
  end

  private def create_plan(bot, map)
    cands = [] of ActionType
    cands << ActionSimple::W if map.inside(bot.x, bot.y + 1)
    cands << ActionSimple::S if map.inside(bot.x, bot.y - 1)
    cands << ActionSimple::A if map.inside(bot.x - 1, bot.y)
    cands << ActionSimple::D if map.inside(bot.x + 1, bot.y)
    bot.plan << cands.sample(@rnd)
    puts "plan:#{bot.plan[0]}"
  end

  private def evaluate_W(bot, map)
    {ActionSimple::W, evaluate_move(bot, map, 0, 1)}
  end

  private def evaluate_S(bot, map)
    {ActionSimple::S, evaluate_move(bot, map, 0, -1)}
  end

  private def evaluate_A(bot, map)
    {ActionSimple::A, evaluate_move(bot, map, -1, 0)}
  end

  private def evaluate_D(bot, map)
    {ActionSimple::D, evaluate_move(bot, map, 1, 0)}
  end

  private def evaluate_move(bot, map, dx, dy)
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

  private def evaluate_move2(bot, map, dx, dy)
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
    # @bbuf.gen += 1
    # @bbuf.set(nx, ny)
    # @apbuf.clear
    # @apbuf << Point.new(nx, ny)
  end

  private def evaluate_E(bot, map)
  end

  private def evaluate_Q(bot, map)
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
      {p.x.abs, p.y.abs}.max.times { a << p }
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
