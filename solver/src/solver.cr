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
    @simulate_types = [] of Array(ActionType)
    initialize_simulate_types
  end

  def initialize_simulate_types
    # @simulate_types << [ActionSimple::W, ActionSimple::W, ActionSimple::W]
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
    time = 0
    next_spawn = [] of Bot
    # puts @map.n_empty
    while @map.n_empty > 0
      time += 1
      @map.bots.each do |bot|
        @map.get_booster(bot)
        action = select_action(bot, @map)
        @map.apply_action(action, bot, next_spawn)
        # puts "action:#{action}"
      end
      # puts "time:#{time}"
      # puts @map
      @map.finalize_turn(next_spawn)
    end
    commands = @map.bots.map { |bot| bot.actions }
    {time, commands}
  end

  private def select_action(bot, map) : ActionType
    # puts "pre plan:#{bot.plan}"
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
      max_actions = [] of Array(ActionType)
      @simulate_types.each do |actions|
        n = simulate(bot, map, actions)
        if n > max_wrapped
          max_wrapped = n
          max_actions.clear
          max_actions << actions
          # puts "#{n} #{max_actions}"
        elsif n > 0 && n == max_wrapped
          max_actions << actions
        end
      end
      if max_wrapped > cur_wrapped
        use_actions = max_actions.sample(@rnd)
        bot.plan.clear
        bot.plan << use_actions[2] << use_actions[1]
        return use_actions[0]
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
    orig_arm = bot.arm.dup
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
    # TODO: consider F and L
    @bbuf.next
    dist_pos = Array(Array(Point)).new
    que = [bot.pos]
    min_dist = 9999
    1.upto(9999) do |dist|
      cpos = [] of Point
      que.each do |cp|
        4.times do |i|
          nx = cp.x + DX[i]
          ny = cp.y + DY[i]
          next if !map.inside(nx, ny) || map.wall[ny][nx] || @bbuf.get(nx, ny)
          @bbuf.set(nx, ny)
          @bbuf.dir[ny][nx] = i
          cpos << Point.new(nx, ny)
          if min_dist == 9999 && !map.wrapped[ny][nx]
            min_dist = dist
          end
        end
      end
      break if dist > min_dist + 2 || cpos.empty?
      dist_pos << cpos
      que = cpos
    end
    if min_dist == 9999
      raise "cannot find wrap pos"
    end

    best_time, best_pos = find_target(bot, map, dist_pos)
    rot = [] of ActionSimple
    bot.rot_cw
    time, pos = find_target(bot, map, dist_pos)
    if time + 1 < best_time
      best_time = time + 1
      best_pos = pos
      rot = [ActionSimple::E]
    end
    bot.rot_cw
    time, pos = find_target(bot, map, dist_pos)
    if time + 2 < best_time
      best_time = time + 2
      best_pos = pos
      rot = [ActionSimple::E, ActionSimple::E]
    end
    bot.rot_cw
    time, pos = find_target(bot, map, dist_pos)
    if time + 1 < best_time
      best_time = time + 1
      best_pos = pos
      rot = [ActionSimple::Q]
    end
    bot.rot_cw
    while pos != bot.pos
      d = @bbuf.dir[pos.y][pos.x]
      pos.x = pos.x - DX[d]
      pos.y = pos.y - DY[d]
      bot.plan << MOVE_ACTIONS[d]
    end
    bot.plan.concat(rot.reverse)
    # puts "plan:#{bot.plan}"
  end

  private def find_target(bot, map, dist_pos)
    dist_pos.each_with_index do |dist_p, i|
      max_n = 0
      max_pos = bot.pos
      dist_p.each do |bp|
        n = map.wrapped[bp.y][bp.x] ? 0 : 1
        bot.arm.each do |ap|
          nx = bp.x + ap.x
          ny = bp.y + ap.y
          if map.inside(nx, ny) && !map.wrapped[ny][nx] && map.visible(bp.x, bp.y, ap.x, ap.y)
            n += 1
          end
        end
        if n > max_n
          max_n = n
          max_pos = bp
        end
      end
      if max_n > 0
        return {i + 1, max_pos}
      end
    end
    {9999, bot.pos}
  end

  private def select_arm(bot, map)
    s = Set(Point).new
    s << Point.new(0, +1)
    s << Point.new(0, -1)
    s << Point.new(1, 0)
    s << Point.new(-1, 0)
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
  property idx, dir, gen

  def initialize
    @idx = Array(Array(Int32)).new
    @dir = Array(Array(Int32)).new
    @gen = 0
  end

  def init(h, w)
    @idx = Array.new(h) { Array(Int32).new(w, 0) }
    @dir = Array.new(h) { Array(Int32).new(w, 0) }
    @gen = 0
  end

  def next
    @gen += 1
  end

  def set(x, y)
    @idx[y][x] = @gen
  end

  def get(x, y)
    @idx[y][x] == @gen
  end
end
