#!/usr/bin/ruby

# a quick and dirty ICMP ping method
# this is NOT thread safe
# and doesn't generate errors
# anything bad happens and it just returns false
# times out after 2 seconds
#
# false = fail
# int = success, RTT
#
# The rtt is rounded to the nearest ms
# 

require 'socket'

# we require ruby 1.9
raise "pinglite requires Ruby 1.9" unless RUBY_VERSION.match(/^1.9/)

def pinglite(host)
	# vars used in packet creation
	payload = "Ruby Quick n Dirty Ping - pinglite"
	pstring = "C2 n3 A#{payload.size.to_s}"
	checksum = 0
	ip = "0"
	
	# id is generated by using the PID up to (32767)
	# then adding a random number up to 32767
	# this should give us a very unique ID for matching return packets
	id_pid = Process.pid & 0x7FFF
	id_rand = rand(32767)
	id = id_pid + id_rand
	
	# the sequence is just a random number (16 bit)
	# again very unique for matching return packets
	# track this in a global var and the ping might be thread safe
	seq = rand(65534)
	
	# create socket
	begin
		sock = Socket.new( :INET, :RAW, 1 )
		sock.bind(Socket.pack_sockaddr_in(0 , "0.0.0.0"))
	rescue
		# failed to bind, not root?
		return false
	end
	
	# craft packet to gereate checksum
	msg = [8, 0, checksum, id, seq, payload].pack(pstring)
	
	# generate checksum
	length = msg.length
	num_short = length / 2
	check = 0
	msg.unpack("n#{num_short}").each do |short|
	    check += short
	end
	if length % 2 > 0
	    check += msg[length-1, 1].unpack('C').first << 8
	end
	check = (check >> 16) + (check & 0xffff)
	checksum = (~((check >> 16) + check) & 0xffff)

	# craft packet with checksum
	msg = [8, 0, checksum, id, seq, payload].pack(pstring)
	
	# send packet
	begin
		start_time = Time.now
		sock.send( msg, 0 ,Socket.pack_sockaddr_in(0 , host) )
	rescue
		# packet could fail here, probably due to host lookup
		return false
	end
	
	# now recieve
	while true do
		loop_time = Time.now
		
		if (loop_time - start_time) > 2.0
			# timeout afer 2 seconds
			return false
		end
		
		# try to read data
		sel = select([sock],nil,nil,0.01)
		
		# loop around again if there is none
		next if sel == nil
	
		begin
			data = sock.recvfrom(1500)[0]
		rescue
			# can't be our reply if it's bigger than 1500
			next
		end
		
		# only need type don't have to decode both
		type = data[20,1].unpack('C')[0]
		if type == 0
			# we got a reply
			rid, rseq = data[24, 4].unpack('n3')
			if ( rid == id && rseq == seq )
				# yay it's ours!
				rtt = sprintf("%.0f", (Time.now - start_time) * 1000)
				return rtt
			end
		end
	end
end