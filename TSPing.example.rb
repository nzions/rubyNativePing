# example of how to use tsping
#
# this will scan a /24 subnet real fast

require './TSPing.rb'

# we need a mutex to conrol the output buffering
mutex = Mutex.new

# create the pinger object
pinger = TSPing.new

# create an array to keep track of all the threads
threads = Array.new

mutex.synchronize { puts "scanning 192.168.0.0/24" }

# now loop through 256 times (0-255)
256.times do |n|
	threads << Thread.new {
		mutex.synchronize { puts "pinging 192.168.0.#{n}" }

		begin
			res = pinger.ping("192.168.0.#{n}")
		rescue
			mutex.synchronize { puts "ping failed for 192.168.0.#{n}: #{$!}" }
		end
		
		if res == false
			mutex.synchronize { puts "192.168.0.#{n} did not respond"	}
		else
			mutex.synchronize { puts "192.168.0.#{n} responded in #{res}ms" }
		end
	}
	
	# add a delay between thread creaton
	# you could skip this... do so at your own risk
	sleep 0.05
end

threads.each do |t|
	t.join
end
