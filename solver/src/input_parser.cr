require "bit_array"

class Map
  property wall, covered : Array(BitArray), booster, bots, beacons

  def initialize(
    @wall : Array(BitArray),
    @booster : Hash(Point, BoosterType),
    @bots : Array(Bot)
  )
    @covered = Array.new(@wall.size) { BitArray.new(@wall[0].size) }
    @beacons = Array(Point).new
  end

  def h
    @wall.size
  end

  def w
    @wall[0].size
  end

  def to_s(io : IO)
    io << "wall\n"
    field = Array.new(h) { |i| Array.new(w) { |j| @wall[i][j] ? '#' : @covered[i][j] ? '.' : '_' } }
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
  property pos, arm, fast_time : Int32, drill_time : Int32

  def initialize(@pos : Point, @arm : Array(Point))
    @fast_time = @drill_time = 0
  end

  def to_s(io : IO)
    io << pos << " " << arm << " ft:#{fast_time} dt:#{drill_time}"
  end

  def inspect(io : IO)
    to_s(io)
  end
end

enum BoosterType
  B; F; L; X; R; C
end

class InputParser
  def self.parse(input : String)
    map_str, point_str, obstacles_str, boosters_str = input.split("#")
    map_edge = parse_map(map_str)
    init_pos = parse_point(point_str)
    obstacles_edge = parse_obsts(obstacles_str)
    wall = create_walls(map_edge, obstacles_edge)
    boosters = parse_boosters(boosters_str, wall.size, wall[0].size)
    init_arms = -1.upto(1).map { |dy| Point.new(init_pos.x, init_pos.y + dy) }.to_a
    Map.new(wall, boosters, [Bot.new(init_pos, init_arms)])
  end

  def self.parse_point(str)
    x, y = str[1..-2].split(",").map(&.to_i)
    Point.new(x, y)
  end

  def self.parse_map(str)
    str.split(/,(?=\()/).map { |s| parse_point(s) }
  end

  def self.parse_obsts(str)
    str.split(";").map { |s| parse_map(s) }
  end

  def self.parse_boosters(str, h, w)
    bs = Hash(Point, BoosterType).new
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
