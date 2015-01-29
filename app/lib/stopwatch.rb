class Stopwatch

  def initialize()
    @start = Time.now
  end

  def elapsed_time
    now = Time.now
    elapsed = now - @start
    # puts 'Started: ' + @start.to_s
    # puts 'Now: ' + now.to_s
    # puts 'Elapsed time: ' +  elapsed.to_s + ' seconds'
    return elapsed.to_s + ' seconds'
  end

end

## Usage

# s = Stopwatch.new
# sleep(2)
# puts s.elapsed_time