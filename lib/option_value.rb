class OptionValue
  attr_accessor :initial_per_share, :drift, :volatility, :charged_per_share,
    :cliff, :duration, :dt, :interest_rate

  def udp
    u = Math.exp(volatility * dt)
    d = Math.exp(-volatility * dt)
    p = (Math.exp(interest_rate * dt) - d) / (u - d)
    { u: u, d: d, p: p }
  end

  # Assume the company is geometric Brownian motion
  def simulate_path
    path = [initial_per_share]
    t = 0
    while t < duration - 1e-6
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
    x
  end

  # P[z > N]
  def self.cdf(z)
    (0.5 * (1.0 + Math.erf((z * 1.0) / 1.4142135623730951)))
  end

  # Generates stock value nodes
  def gen_binomial_tree_prices
    u = udp[:u]
    d = udp[:d]
    tree = [[initial_per_share]]
    t = 0
    while t < duration - 1e-6
      t += dt
      this_arr = tree.last.collect { |s| s * d }
      this_arr << tree.last.last * u
      tree << this_arr
    end
    tree
  end

  def val_tree
    stock_prices = gen_binomial_tree_prices
    end_prices = stock_prices.last
    end_vals = end_prices.map { |s| (-charged_per_share + s) * duration }
    val_tree = [end_vals]
    # don't need other stock prices
    p = udp[:p]
    while val_tree.first.size > 1
      last_vals = val_tree.first
      these_vals = []
      (1..(last_vals.size - 1)).each do |idx|
        these_vals << (p * last_vals[idx] + (1 - p) * last_vals[idx - 1])
      end
      val_tree = [these_vals] + val_tree
    end
    val_tree
  end

  def sim_up_down
    up_down = []
    t = 0
    while t < duration - 1e-6
      t += dt
      up_down << (rand > 0.5)
    end
    up_down
  end

  def binomial_tree_path_sim(n = 100)
    # -1st do binomial tree to figure out how much this contract is worth
    #  at a bunch of different nodes:
    #  At expiration, V(T,S) = (-charged_per_share + share_price * 1) * T
    #  (1 because we assume we get 1 share per unit time)
    tree_of_vals = val_tree

    # -2nd, we can simulate a bunch of paths using the values from part
    #  (1), but killing the simulation if we hit a boundary whereby
    #  our E[dV] < 0
    p = udp[:p]
    sum_val = 0
    sum_lv = 0
    (1..n).each do |sim_num|
      up_down = sim_up_down
      idxs_for_up_down = [0] # the path we take based on the ups and downs
      up_down.each do |ud|
        idxs_for_up_down << (idxs_for_up_down.last + (ud ? 1 : 0))
      end
      # now move through the prices in the tree, stopping if
      # E[dV] of moving again is negative
      this_val = nil
      this_lv = nil
      idxs_for_up_down.each_with_index do |vidx, tidx|
        # If it's not the first iteration, it's after the cliff, and
        # it's not the last index, we have the option of stopping
        # and not taking a step. Do so if E[dV] is negative
        if !this_val.nil? && (tidx * dt > cliff - 1e-6) && tidx < idxs_for_up_down.size - 1
          e_dv = p * (tree_of_vals[tidx + 1][vidx + 1]) +
                  (1 - p) * (tree_of_vals[tidx + 1][vidx]) -
                  this_val
          if e_dv < 0
            this_lv = tidx
            break
          end
        end
        this_lv = tidx
        this_val = tree_of_vals[tidx][vidx]
      end
      sum_lv += this_lv
      sum_val += this_val
    end
    {
      val: sum_val.to_f / n,
      lv:  sum_lv.to_f / n * dt
    }
  end

  # Artsy:
  #  drift:             doesn't matter because we are risk neutral (we can repro this option by buying shares)
  #  volatility:        60% feels about right
  #  charged_per_share: In 1 year of work, I could keep (after taxes), minimum, 1.5x what they're paying me in equity
  #  cliff:             1 year (meaning no optionality for the first year)
  #  duration:          4 years total of optionality
  #  dt:                0.01 is pretty darn convergent
  #  interest_rate:     I'd be charged 10% by a bank to borrow against future earnings (say, at GS) to buy Artsy stock
  #
  # Conclusion of simulation:
  #  OptionValue.new(0.2, 0.6, 1.5, 1, 4, 1.0 / 12, 0.1).binomial_tree_path_sim(10000)
  #  {:val=>-0.24797482805638846, :lv=>1.0821916666666667}
  # ...it's slightly negative financially to work at Artsy, and optimal leave is 1.12 years
  # Interestingly, it's POSITIVE if there is no cliff...
  # Here's me today:
  #  OptionValue.new(0.2, 0.6, 1.5, 5.0 / 12, 4.0 - 7.0 / 12, 1.0 / 12, 0.1 ).binomial_tree_path_sim(10000)
  #  {:val=>-0.24629676748093784, :lv=>0.5000749999999999} # it's the same! which is expected...
  def initialize(drift, volatility, charged_per_share,
      cliff = 1, duration = 4, dt = 0.01, interest_rate = 0.1)
    self.initial_per_share = 1
    self.drift             = drift
    self.volatility        = volatility
    self.charged_per_share = charged_per_share
    self.cliff             = cliff
    self.duration          = duration
    self.dt                = dt
    self.interest_rate     = interest_rate
  end
end
