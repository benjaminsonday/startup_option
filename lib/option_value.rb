class OptionValue
  attr_accessor :initial_per_share, :drift, :volatility, :charged_per_share, :cliff, :duration, :dt

  # Assume the company is geometric Brownian motion
  def simulate_path
    path = [initial_per_share]
    t = 0
    until t > duration
      t += dt
      path << path.last * Math.exp(drift * dt + volatility * Math.sqrt(dt) * OptionValue.gaussian(0, 1))
    end
    path
  end

  def self.gaussian(mean, stddev)
    theta = 2 * Math::PI * rand
    rho = Math.sqrt(-2 * Math.log(1 - rand))
    scale = stddev * rho
    x = mean + scale * Math.cos(theta)
    # y = mean + scale * Math.sin(theta)
    return x
  end

  # P[z > N]
  def self.cdf(z)
    (0.5 * (1.0 + Math.erf((z*1.0)/1.4142135623730951)))
  end

  def delta(val_per_share, time_left)
    dist_from_mean = val_per_share - charged_per_share
    to_z = dist_from_mean / volatility / Math.sqrt(time_left)
  end

  # TODO: this!
  def binomial_tree
    path = simulate_path
    # 1st do binomial tree to figure out how much this contract is worth
    # at a bunch of different nodes:
    # At exp, V(T,S) = (-charged_per_share + share_price * 1) * T
    # 2nd, we can find the nodes marking the boundary between
    # profitable and not profitable by marking a node whenever the
    # expected dV in some dt is negative.
    # 3rd, we can simulate a bunch of paths using the values from part
    # (1), but killing the simulation if we hit this boundary
  end

  # initial_per_share: FMV of shares on day 0
  # charged_per_share: how much charged per share per unit time
  # ...assuming we get one share per unit time...
  #
  # Artsy is roughly OptionValue.new(1, 0.2, 0.4, 3); I can make
  # 3x more somewhere else at Artsy's current market price, but
  # it grows at about 20% per year, and the volatility is about 40%.
  # This means I break even barely.
  def initialize(initial_per_share, drift, volatility, charged_per_share,
      cliff = 1, duration = 4, dt = 0.01)
    self.initial_per_share = initial_per_share
    self.drift             = drift
    self.volatility        = volatility
    self.charged_per_share = charged_per_share
    self.cliff             = cliff
    self.duration          = duration
    self.dt                = dt
  end

  # Operate according to naive heuristic of: void contract
  # at decide point if value is less than per share
  def simulate_runs(n = 1000, decide_point)
    sum_value = 0.0
    (1..n).each do |idx|
      puts "Running #{idx}" if idx % 100 == 0
      path = simulate_path
      val_at_decide_point = path[(decide_point / dt).floor]
      if val_at_decide_point < charged_per_share
        sum_value += decide_point * (val_at_decide_point - charged_per_share)
      else
        sum_value += duration * (path.last - charged_per_share)
      end
    end
    sum_value / n
  end
end
