require "random"
require "./defs"

MOVE_DOUBLE = (1 << 4)
SMALL_GROUP = 200

class Solver
  @map : Map
  @empty_dists : Array(Array(Int32)) | Nil
  @max_search_base_dist : Int32
  @wrap_score : Array(Array(Int32))

  def initialize(@orig_map : Map, @tl : Int64)
    @map = @orig_map.clone
    @rnd = Random.new(2)
    @bbuf = BFSBuffer.new
    @simulate_types = [] of Array(ActionType)
    @max_search_base_dist = ((@map.h + @map.w) * 0.2).to_i
    @wrap_score = Array.new(@map.h) { Array.new(@map.w, 0) }
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
    turn = 1
    while prev_time + max_elapse < @tl
      score, commands = solve_single(res[0])
      if score < res[0]
        res = {score, commands}
        STDERR.puts("turn:#{turn} score:#{score}")
      end
      cur_time = Time.now.to_unix_ms
      max_elapse = {max_elapse, cur_time - prev_time}.max
      prev_time = cur_time
      turn += 1
    end
    STDERR.puts("total turn:#{turn} max_elapse:#{max_elapse}")
    res
  end

  private def solve_single(best_result) : Tuple(Int32, Array(Array(ActionType)))
    @map = @orig_map.clone
    @map.bots.each do |bot|
      init_bot_base_dist(bot, bot.pos, @map)
    end
    @empty_dists = nil
    time = 0
    next_spawn = [] of Bot
    while @map.n_empty > 0
      time += 1
      if time == best_result # prune
        return {best_result, [] of Array(ActionType)}
      end
      prev_empty = @map.n_empty
      @map.bots.each do |bot|
        @map.get_booster(bot)
        action = select_action(bot, @map)
        @map.apply_action(action, bot, next_spawn)
        # puts "action:#{action}"
      end
      if @map.n_empty != prev_empty
        @map.bots.each do |bot|
          bot.plan_force = false
        end
      end
      # puts "time:#{time}"
      # puts @map
      @map.finalize_turn(next_spawn)
    end
    commands = @map.bots.map { |bot| bot.actions }
    {time, commands}
  end

  private def select_action(bot, map) : ActionType
    return ActionSimple::Z if map.n_empty == 0
    bot.plan_force = false if bot.plan.empty?
    if map.n_B > 0
      bot.clear_plan
      return select_arm(bot, map)
    elsif map.n_F > 0 && bot.fast_time == 0
      bot.clear_plan
      return ActionSimple::F
    elsif bot.plan.size >= 3 || bot.plan_force
      return bot.plan.pop
    else
      do_simulate = update_wrap_score(bot, map)
      if do_simulate
        cur_wrapped = bot.plan.empty? ? 0 : simulate(bot, map, bot.plan.reverse)
        max_wrapped = 0
        max_actions = [] of Array(ActionType)
        @simulate_types.each do |actions|
          n = simulate(bot, map, actions)
          if n > max_wrapped
            max_wrapped = n
            max_actions.clear
            max_actions << actions
          elsif n > 0 && n == max_wrapped
            max_actions << actions
          end
        end
        if max_wrapped > cur_wrapped
          use_actions = max_actions.sample(@rnd)
          bot.clear_plan
          bot.plan << use_actions[2] << use_actions[1]
          bot.plan_force = max_wrapped > SMALL_GROUP
          return use_actions[0]
        end
      else
        bot.clear_plan
      end
      if bot.plan.empty?
        create_plan(bot, map)
      end
      return bot.plan.pop if !bot.plan.empty?
    end
    raise "why Z???"
    return ActionSimple::Z
  end

  private def simulate(bot, map, actions)
    orig_pos = bot.pos
    orig_arm = bot.arm.dup
    wrapped = [] of Point
    booster_pos = [] of Point
    score = 0
    begin
      actions.each_with_index do |action, i|
        rep = bot.fast_time > i && action != ActionSimple::E && action != ActionSimple::Q ? 2 : 1
        rep.times do |j|
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
          if !map.inside(bot.x, bot.y) || (bot.drill_time <= i && map.wall[bot.y][bot.x])
            return 0 if j == 0
            case action
            when ActionSimple::W
              bot.y -= 1
            when ActionSimple::S
              bot.y += 1
            when ActionSimple::A
              bot.x += 1
            when ActionSimple::D
              bot.x -= 1
            end
          else
            score += collect_wrapped(bot, map, wrapped)
          end
        end
        if map.booster.has_key?(bot.pos) && !booster_pos.includes?(bot.pos)
          booster_pos << bot.pos
        end
      end
      score += booster_pos.size * 50
    ensure
      wrapped.each do |p|
        map.wrapped[p.y][p.x] = false
      end
      bot.pos = orig_pos
      bot.arm = orig_arm
    end
  end

  private def collect_wrapped(bot, map, wrapped)
    score = 0
    bot.arm.each do |ap|
      x = bot.x + ap.x
      y = bot.y + ap.y
      if map.inside(x, y) && !map.wrapped[y][x] && map.visible(bot.x, bot.y, ap.x, ap.y)
        map.wrapped[y][x] = true
        wrapped << Point.new(x, y)
        score += @wrap_score[y][x]
      end
    end
    if !map.wrapped[bot.y][bot.x]
      map.wrapped[bot.y][bot.x] = true
      wrapped << bot.pos
      score += @wrap_score[bot.y][bot.x]
    end
    score
  end

  private def create_plan(bot, map)
    # TODO: consider L, T and other bots
    @bbuf.next
    @bbuf.set(bot.x, bot.y)
    dist_pos = Array(Array(Point)).new
    que = [bot.pos]
    min_dist = 9999
    min_base_dist = 9999
    1.upto(9999) do |dist|
      cpos = [] of Point
      cpos_prior = [] of Point
      reached = [] of Point
      que.each do |cp|
        if dist <= bot.fast_time
          4.times do |i|
            nx = cp.x + DX[i]
            ny = cp.y + DY[i]
            next if !map.inside(nx, ny) || (bot.drill_time < dist && map.wall[ny][nx])
            @bbuf.set(nx, ny)
            nx += DX[i]
            ny += DY[i]
            mv2 = MOVE_DOUBLE
            if !map.inside(nx, ny) || (bot.drill_time < dist && map.wall[ny][nx])
              nx -= DX[i]
              ny -= DY[i]
              mv2 = 0
            end
            next if @bbuf.get(nx, ny)
            @bbuf.set(nx, ny)
            @bbuf.dir[ny][nx] = i | mv2
            np = Point.new(nx, ny)
            if !map.wrapped[ny][nx]
              min_dist = {min_dist, dist}.min
              min_base_dist = {min_base_dist, bot.base_dist[ny][nx]}.min
              reached << np
            else
              if map.booster.has_key?(np)
                cpos_prior << np
              else
                cpos << np
              end
            end
          end
        else
          4.times do |i|
            nx = cp.x + DX[i]
            ny = cp.y + DY[i]
            next if !map.inside(nx, ny) || map.wall[ny][nx] || @bbuf.get(nx, ny)
            @bbuf.set(nx, ny)
            @bbuf.dir[ny][nx] = i
            np = Point.new(nx, ny)
            if !map.wrapped[ny][nx]
              min_dist = {min_dist, dist}.min
              min_base_dist = {min_base_dist, bot.base_dist[ny][nx]}.min
              reached << np
            else
              if map.booster.has_key?(np)
                cpos_prior << np
              else
                cpos << np
              end
            end
          end
        end
      end
      cpos = cpos_prior + cpos
      dist_pos << reached + cpos
      break if dist > min_dist + @max_search_base_dist || cpos.empty?
      que = cpos
    end
    if min_dist == 9999
      raise "cannot find wrap pos" if bot.fast_time == 0
      resque_wandering_wheel(bot, map)
      return
    end

    # puts "min_base_dist:#{min_base_dist} min_dist:#{min_dist}"
    if min_base_dist > min_dist
      # puts "change base to #{bot.pos} from #{bot.base}"
      init_bot_base_dist(bot, bot.pos, map)
      min_base_dist = min_dist
    end

    max_accept_dist = min_base_dist + 2 + {min_base_dist + 2, bot.fast_time}.min
    best_time, best_pos = find_target(bot, map, dist_pos, max_accept_dist)
    rot = [] of ActionSimple
    if bot.fast_time == 0 || min_dist < bot.fast_time - 2
      bot.rot_cw
      time, pos = find_target(bot, map, dist_pos, max_accept_dist)
      if time + 1 < best_time
        best_time = time + 1
        best_pos = pos
        rot = [ActionSimple::E]
      end
      bot.rot_cw
      time, pos = find_target(bot, map, dist_pos, max_accept_dist)
      if time + 2 < best_time
        best_time = time + 2
        best_pos = pos
        rot = [ActionSimple::E, ActionSimple::E]
      end
      bot.rot_cw
      time, pos = find_target(bot, map, dist_pos, max_accept_dist)
      if time + 1 < best_time
        best_time = time + 1
        best_pos = pos
        rot = [ActionSimple::Q]
      end
      bot.rot_cw
    end
    while best_pos != bot.pos
      d = @bbuf.dir[best_pos.y][best_pos.x]
      if (d & MOVE_DOUBLE) != 0
        d -= MOVE_DOUBLE
        best_pos.x = best_pos.x - DX[d] * 2
        best_pos.y = best_pos.y - DY[d] * 2
      else
        best_pos.x = best_pos.x - DX[d]
        best_pos.y = best_pos.y - DY[d]
      end
      bot.plan << MOVE_ACTIONS[d]
    end
    bot.plan.concat(rot.reverse)
    if bot.plan.size > (map.w + map.h) / 8 && map.n_L > 0 && bot.fast_time == 0
      drill_plan = create_drill_plan(bot, map, bot.plan.size)
      if drill_plan
        bot.plan = drill_plan
        bot.plan_force = true
      end
    end
    # puts "plan:#{bot.plan}"
  end

  private def find_target(bot, map, dist_pos, accept_base_dist)
    dist_pos.each_with_index do |dist_p, i|
      max_n = 0
      max_pos = bot.pos
      dist_p.each do |bp|
        n = 0
        if !map.wrapped[bp.y][bp.x]
          n = 1
        end
        bot.arm.each do |ap|
          nx = bp.x + ap.x
          ny = bp.y + ap.y
          if map.inside(nx, ny) && !map.wrapped[ny][nx] && map.visible(bp.x, bp.y, ap.x, ap.y)
            n += 1
          end
        end
        if n > max_n && bot.base_dist[bp.y][bp.x] <= accept_base_dist
          max_n = n
          max_pos = bp
        end
      end
      if max_n > 0
        # puts "target #{i + 1} #{max_pos}"
        return {i + 1, max_pos}
      end
    end
    {9999, bot.pos}
  end

  private def resque_wandering_wheel(bot, map)
    if @empty_dists == nil
      ed = Array.new(map.h) { Array.new(map.w, 9999) }
      que = [] of Point
      map.h.times do |i|
        map.w.times do |j|
          if !map.wrapped[i][j]
            que << Point.new(j, i)
            ed[i][j] = 0
          end
        end
      end
      dist = 1
      while !que.empty?
        nq = [] of Point
        que.each do |p|
          4.times do |i|
            nx = p.x + DX[i]
            ny = p.y + DY[i]
            if map.inside(nx, ny) && !map.wall[ny][nx] && ed[ny][nx] == 9999
              nq << Point.new(nx, ny)
              ed[ny][nx] = dist
            end
          end
        end
        dist += 1
        que = nq
      end
      @empty_dists = ed
    end
    ed = @empty_dists.not_nil!
    dir = 0.upto(3).min_of do |i|
      nx = bot.x + DX[i]
      ny = bot.y + DY[i]
      if map.inside(nx, ny) && !map.wall[ny][nx]
        {ed[ny][nx], i}
      else
        {9999, i}
      end
    end
    if dir[0] > ed[bot.y][bot.x]
      bot.plan << ActionSimple::Z
    else
      bot.plan << {ActionSimple::W, ActionSimple::S, ActionSimple::A, ActionSimple::D}[dir[1]]
    end
  end

  private def create_drill_plan(bot, map, limit)
    @bbuf.next
    que = [bot.pos]
    @bbuf.set(bot.x, bot.y)
    target_pos = nil
    {30, limit - 3}.min.times do |i|
      nq = [] of Point
      que.each do |p|
        4.times do |j|
          nx = p.x + DX[j]
          ny = p.y + DY[j]
          next if !map.inside(nx, ny) || @bbuf.get(nx, ny)
          @bbuf.set(nx, ny)
          @bbuf.dir[ny][nx] = j
          if !map.wrapped[ny][nx]
            target_pos = Point.new(nx, ny)
            break
          end
          nq << Point.new(nx, ny)
        end
      end
      break if target_pos
      que = nq
    end
    return nil if !target_pos
    plan = [] of ActionType
    while target_pos != bot.pos
      d = @bbuf.dir[target_pos.y][target_pos.x]
      target_pos.x = target_pos.x - DX[d]
      target_pos.y = target_pos.y - DY[d]
      plan << MOVE_ACTIONS[d]
    end
    plan << ActionSimple::L
    plan
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

  private def init_bot_base_dist(bot, pos, map)
    bot.base = pos
    @bbuf.next
    @bbuf.set(pos.x, pos.y)
    que = [pos]
    dist = 1
    while !que.empty?
      nq = [] of Point
      que.each do |p|
        4.times do |i|
          nx = p.x + DX[i]
          ny = p.y + DY[i]
          if map.inside(nx, ny) && !map.wall[ny][nx] && !@bbuf.get(nx, ny)
            @bbuf.set(nx, ny)
            bot.base_dist[ny][nx] = dist
            nq << Point.new(nx, ny)
          end
        end
      end
      dist += 1
      que = nq
    end
  end

  private def update_wrap_score(bot, map)
    len = bot.arm.max_of { |p| {p.x.abs, p.y.abs}.max } + 3
    l = {bot.x - len, 0}.max
    r = {bot.x + len, map.w - 1}.min
    b = {bot.y - len, 0}.max
    t = {bot.y + len, map.h - 1}.min
    b.upto(t) do |i|
      l.upto(r) do |j|
        @wrap_score[i][j] = -1
      end
    end
    any = false
    max_que_size = (map.n_empty + 19) / 20
    max_len = (map.h + map.w) / 10
    b.upto(t) do |i|
      l.upto(r) do |j|
        next if @wrap_score[i][j] != -1
        next if map.wrapped[i][j]
        @bbuf.next
        @bbuf.set(j, i)
        any = true
        que = [Point.new(j, i)]
        idx = 0
        score = SMALL_GROUP
        while idx < que.size && que.size < max_que_size && score == SMALL_GROUP
          cur = que[idx]
          4.times do |k|
            nx = cur.x + DX[k]
            ny = cur.y + DY[k]
            next if !map.inside(nx, ny) || map.wrapped[ny][nx]
            if @bbuf.get(nx, ny)
              if l <= nx && nx <= r && b <= ny && ny <= t && @wrap_score[ny][nx] == 1
                score = 1
                break
              else
                next
              end
            end
            @bbuf.set(nx, ny)
            if nx < bot.x - max_len || bot.x + max_len < nx || ny < bot.y - max_len || bot.y + max_len < ny
              score = 1
              break
            end
            que << Point.new(nx, ny)
          end
          idx += 1
        end
        if que.size >= max_que_size
          score = 1
        end
        que.each do |p|
          @wrap_score[p.y][p.x] = score
        end
      end
    end
    return false if !any
    b.upto(t) do |i|
      l.upto(r) do |j|
        next if @wrap_score[i][j] == -1
        neighbor = (4.times.count do |k|
          nx = j + DX[k]
          ny = i + DY[k]
          map.inside(nx, ny) && !map.wrapped[ny][nx]
        end)
        @wrap_score[i][j] += (4 - neighbor) ** 2
      end
    end
    true
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
