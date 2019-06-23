require "bit_array"

DX           = {0, 0, -1, 1}
DY           = {1, -1, 0, 0}
MOVE_ACTIONS = {ActionSimple::W, ActionSimple::S, ActionSimple::A, ActionSimple::D}

class Map
  property wall, wrapped : Array(BitArray), booster, bots, beacons, n_empty : Int32
  property n_B, n_F, n_L, n_R, n_C

  def initialize(
    @wall : Array(BitArray),
    @booster : Hash(Point, BoosterType),
    bot : Bot
  )
    @bots = Array.new(1, bot)
    @wrapped = Array.new(@wall.size) { |i| wall[i][0, w] }
    @wrapped[bot.y][bot.x] = true
    bot.arm.each do |ap|
      ax = bot.x + ap.x
      ay = bot.y + ap.y
      if 0 <= ax && ax < w && 0 <= ay && ay < h
        @wrapped[ay][ax] = true
      end
    end
    @beacons = Array(Point).new
    @n_empty = @wrapped.map { |row| row.count(false) }.sum
    @n_B = @n_F = @n_L = @n_R = @n_C = 0
  end

  def initialize(
    @wall : Array(BitArray),
    @wrapped : Array(BitArray),
    @booster : Hash(Point, BoosterType),
    @bots : Array(Bot),
    @beacons : Array(Point),
    @n_empty : Int32,
    @n_B,
    @n_F,
    @n_L,
    @n_R,
    @n_C
  )
  end

  def clone
    new_wall = Array.new(h) { |i| @wall[i][0, w] }
    new_wrapped = Array.new(h) { |i| @wrapped[i][0, w] }
    Map.new(
      new_wall, new_wrapped, @booster.clone, @bots.clone, @beacons.dup, @n_empty,
      @n_B, @n_F, @n_L, @n_R, @n_C
    )
  end

  def h
    @wall.size
  end

  def w
    @wall[0].size
  end

  def get_booster(bot)
    b = @booster.fetch(bot.pos, nil)
    if b && b != BoosterType::X
      @booster.delete(bot.pos)
      case b
      when BoosterType::B
        @n_B += 1
      when BoosterType::F
        @n_F += 1
      when BoosterType::L
        @n_L += 1
      when BoosterType::R
        @n_R += 1
      when BoosterType::C
        @n_C += 1
      end
    end
  end

  def apply_action(action, bot, next_spawn)
    bot.actions << action
    case action
    when ActionSimple::W
      bot.move(0, 1, self)
    when ActionSimple::S
      bot.move(0, -1, self)
    when ActionSimple::A
      bot.move(-1, 0, self)
    when ActionSimple::D
      bot.move(1, 0, self)
    when ActionSimple::E
      bot.rot_cw
      wrap(bot)
    when ActionSimple::Q
      bot.rot_ccw
      wrap(bot)
    when ActionSimple::F
      @n_F -= 1
      bot.fast_time = 51
    when ActionSimple::L
      @n_L -= 1
      bot.drill_time = 31
    when ActionSimple::R
      @n_R -= 1
      @beacons << bot.pos
    when ActionSimple::C
      @n_C -= 1
      next_spawn << Bot.new(bot.pos)
    when ActionB
      @n_B -= 1
      bot.arm << Point.new(action.x, action.y)
      wrap(bot.x, bot.y, action.x, action.y)
    when ActionT
      bot.pos.x = action.x
      bot.pos.y = action.y
      wrap(bot)
    end
    bot.fast_time -= 1 if bot.fast_time > 0
    bot.drill_time -= 1 if bot.drill_time > 0
  end

  def wrap(bot)
    bot.arm.each do |ap|
      wrap(bot.x, bot.y, ap.x, ap.y)
    end
    wrap(bot.x, bot.y, 0, 0)
  end

  def wrap(bx, by, dx, dy)
    x = bx + dx
    y = by + dy
    if inside(x, y) && !@wrapped[y][x] && visible(bx, by, dx, dy)
      @wrapped[y][x] = true
      @n_empty -= 1
    end
  end

  def finalize_turn(next_spawn)
    @bots.concat(next_spawn)
    next_spawn.each { |b| wrap(b) }
    next_spawn.clear
  end

  def visible(bx, by, dx, dy)
    return !@wall[by + dy][bx + dx] if {dx.abs, dy.abs}.max <= 1
    if dx < 0
      bx += dx
      by += dy
      dx *= -1
      dy *= -1
    end
    ex = bx + dx
    ey = by + dy
    my = dy.sign
    if dx == 0
      while by != ey
        by += my
        return false if @wall[by][bx]
      end
    elsif dy == 0
      while bx != ex
        bx += 1
        return false if @wall[by][bx]
      end
    elsif dy > 0
      div = 2 * dx
      by = (by * 2 + 1) * dx
      ny = by + dy
      (by / div).upto((ny - 1) / div) do |y|
        return false if @wall[y][bx]
      end
      by = ny
      (bx + 1).upto(ex - 1) do |x|
        ny = by + dy * 2
        (by / div).upto((ny - 1) / div) do |y|
          return false if @wall[y][x]
        end
        by = ny
      end
      ny = by + dy
      (by / div).upto((ny - 1) / div) do |y|
        return false if @wall[y][ex]
      end
    else
      div = 2 * dx
      by = (by * 2 + 1) * dx
      ny = by + dy
      (ny / div).upto((by - 1) / div) do |y|
        return false if @wall[y][bx]
      end
      by = ny
      (bx + 1).upto(ex - 1) do |x|
        ny = by + dy * 2
        (ny / div).upto((by - 1) / div) do |y|
          return false if @wall[y][x]
        end
        by = ny
      end
      ny = by + dy
      (ny / div).upto((by - 1) / div) do |y|
        return false if @wall[y][ex]
      end
    end
    return true
  end

  def inside(x, y)
    0 <= x && x < w && 0 <= y && y < h
  end

  def to_s(io : IO)
    io << "n_empty:#{n_empty}\nwall\n"
    field = Array.new(h) { |i| Array.new(w) { |j| @wall[i][j] ? '#' : @wrapped[i][j] ? '.' : '_' } }
    @bots.each { |bot| field[bot.y][bot.x] = '@' }
    field.reverse_each { |row| io << row.join << "\n" }
    io << booster << "\nbots\n"
    @bots.each { |bot| io << bot << "\n" }
    io
  end

  def inspect(io : IO)
    to_s(io)
  end
end

struct Point
  property x, y

  def initialize(@x : Int32, @y : Int32)
  end

  def to_s(io : IO)
    io << "(#{@x},#{@y})"
  end

  def inspect(io : IO)
    to_s(io)
  end

  def hash(hasher)
    hasher = @x.hash(hasher)
    hasher = @y.hash(hasher)
  end
end

class Bot
  property pos, arm : Array(Point), fast_time, drill_time, actions, plan

  def initialize(@pos : Point)
    @fast_time = @drill_time = 0
    @arm = -1.upto(1).map { |dy| Point.new(1, dy) }.to_a
    @actions = [] of ActionType
    @plan = [] of ActionType
  end

  def initialize(
    @pos : Point, @arm : Array(Point), @fast_time : Int32, @drill_time : Int32,
    @actions : Array(ActionType), @plan : Array(ActionType)
  )
  end

  def x
    @pos.x
  end

  def x=(nx)
    @pos.x = nx
  end

  def y
    @pos.y
  end

  def y=(ny)
    @pos.y = ny
  end

  def move(dx, dy, map)
    move1(dx, dy, map)
    move1(dx, dy, map) if @fast_time > 0
  end

  private def move1(dx, dy, map)
    nx = x + dx
    ny = y + dy
    return if !map.inside(nx, ny)
    return if map.wall[ny][nx] && @drill_time == 0
    @pos.x += dx
    @pos.y += dy
    map.wall[ny][nx] = false if @drill_time > 0
    map.wrap(self)
  end

  def rot_cw
    @arm.size.times do |i|
      @arm[i] = Point.new(@arm[i].y, -@arm[i].x)
    end
  end

  def rot_ccw
    @arm.size.times do |i|
      @arm[i] = Point.new(-@arm[i].y, @arm[i].x)
    end
  end

  def clone
    Bot.new(@pos, @arm.dup, @fast_time, @drill_time, @actions.dup, @plan.dup)
  end

  def to_s(io : IO)
    io << @pos << " " << @arm << " ft:#{@fast_time} dt:#{@drill_time}"
  end

  def inspect(io : IO)
    to_s(io)
  end
end

enum BoosterType
  B; F; L; X; R; C
end

enum ActionSimple
  W; S; A; D; Z; E; Q; F; L; R; C
end

abstract struct ActionWithCoord
  getter x, y

  def initialize(@ch : Char, @x : Int32, @y : Int32)
  end

  def to_s(io : IO)
    io << @ch << "(" << @x << "," << @y << ")"
  end

  def inspect(io : IO)
    to_s(io)
  end
end

struct ActionB < ActionWithCoord
  def initialize(x : Int32, y : Int32)
    super('B', x, y)
  end
end

struct ActionT < ActionWithCoord
  def initialize(x : Int32, y : Int32)
    super('T', x, y)
  end
end

alias ActionType = ActionSimple | ActionB | ActionT

class InputParser
  def self.parse(input : String)
    map_str, point_str, obstacles_str, boosters_str = input.strip.split("#")
    map_edge = parse_map(map_str)
    init_pos = parse_point(point_str)
    obstacles_edge = parse_obsts(obstacles_str)
    wall = create_walls(map_edge, obstacles_edge)
    boosters = parse_boosters(boosters_str, wall.size, wall[0].size)
    Map.new(wall, boosters, Bot.new(init_pos))
  end

  def self.parse_point(str)
    x, y = str[1..-2].split(",").map(&.to_i)
    Point.new(x, y)
  end

  def self.parse_map(str)
    return [] of Point if str.empty?
    str.split(/,(?=\()/).map { |s| parse_point(s) }
  end

  def self.parse_obsts(str)
    str.split(";").map { |s| parse_map(s) }
  end

  def self.parse_boosters(str, h, w)
    bs = Hash(Point, BoosterType).new
    if !str.empty?
      str.split(";").each do |s|
        p = parse_point(s[1..])
        t = case s[0]
            when 'B'
              BoosterType::B
            when 'F'
              BoosterType::F
            when 'L'
              BoosterType::L
            when 'X'
              BoosterType::X
            when 'R'
              BoosterType::R
            when 'C'
              BoosterType::C
            end
        bs[p] = t if t
      end
    end
    bs
  end

  def self.create_walls(map_edge, obstacles_edge)
    max_x = map_edge.max_of(&.x)
    max_y = map_edge.max_of(&.y)
    f = Array.new(max_y) { Array.new(max_x, 0) }
    init_walls(f, map_edge, 1)
    obstacles_edge.each { |oe| init_walls(f, oe, -1) }
    bfs_walls(f)
    walls = Array.new(max_y) { BitArray.new(max_x) }
    max_y.times { |i| max_x.times { |j| walls[i][j] = true if f[i][j] == -1 } }
    walls
  end

  private def self.init_walls(field, edges, value)
    return if edges.empty?
    es = edges + [edges[0]]
    edges.size.times do |i|
      p0 = es[i]
      p1 = es[i + 1]
      if p0.x < p1.x
        p0.x.upto(p1.x - 1) do |i|
          field[p0.y - 1][i] = -value if p0.y - 1 >= 0
          field[p0.y][i] = value if p0.y < field.size
        end
      elsif p0.x > p1.x
        p1.x.upto(p0.x - 1) do |i|
          field[p0.y - 1][i] = value if p0.y - 1 >= 0
          field[p0.y][i] = -value if p0.y < field.size
        end
      elsif p0.y < p1.y
        p0.y.upto(p1.y - 1) do |i|
          field[i][p0.x - 1] = value if p0.x - 1 >= 0
          field[i][p0.x] = -value if p0.x < field[0].size
        end
      else
        p1.y.upto(p0.y - 1) do |i|
          field[i][p0.x - 1] = -value if p0.x - 1 >= 0
          field[i][p0.x] = value if p0.x < field[0].size
        end
      end
    end
  end

  private def self.bfs_walls(field)
    h = field.size
    w = field[0].size
    q = [] of Tuple(Point, Int32)
    h.times { |i| w.times { |j| q << {Point.new(j, i), field[i][j]} if field[i][j] != 0 } }
    while !q.empty?
      e = q.shift
      x = e[0].x
      y = e[0].y
      if x > 0 && field[y][x - 1] == 0
        field[y][x - 1] = e[1]
        q << {Point.new(x - 1, y), e[1]}
      end
      if x + 1 < w && field[y][x + 1] == 0
        field[y][x + 1] = e[1]
        q << {Point.new(x + 1, y), e[1]}
      end
      if y > 0 && field[y - 1][x] == 0
        field[y - 1][x] = e[1]
        q << {Point.new(x, y - 1), e[1]}
      end
      if y + 1 < h && field[y + 1][x] == 0
        field[y + 1][x] = e[1]
        q << {Point.new(x, y + 1), e[1]}
      end
    end
  end
end
