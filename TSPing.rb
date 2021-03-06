#!/usr/bin/ruby

# Thread Safe Ping
# hopefully this ping is thread safe
# minimum RTT on windows is 15-30ms due to windows only updating the system time every 10-15ms
# if you need better accuracy use linux


require 'socket'

# we require ruby 1.9
raise "TSPing requires Ruby 1.9" unless RUBY_VERSION.match(/^1.9/)

class TSPing
	@@mutex = nil
	@@seqs = nil
	@@last_seq = nil
	
	def initialize
		if @@mutex == nil
			@@mutex = Mutex.new
			@@seqs = Hash.new
			@@last_seq = 0
		end
	end
	
	def ping(host,tout=2000)
		# ping(<host>, <timeout in ms>)
		# vars used in packet creation
		payload = "TSPing 1234567"
		pstring = "C2 n3 A#{payload.size.to_s}"
		checksum = 0
		ip = "0"
		timeout = tout.to_f / 1000.00

		# id is generated by using the PID
		id = Process.pid & 0xFFFF
		
		# the sequence is the next unused 16 bit integer so we can have about 64000 simultaneous pings running
		# i suspect you'd run out of threads or memory before that happens
		seq = nil
		@@mutex.synchronize {
			seq = @@last_seq & 0xFFFF
			if @@seqs.has_key?(seq) 
				raise "Could not crete sequence id, wow are we really pinging 65k hosts?"
			end
			@@seqs[seq] = host
			@@last_seq += 1
		}
		
		# create socket
		begin
			sock = Socket.new( Socket::PF_INET, Socket::SOCK_RAW, Socket::IPPROTO_ICMP )
			sock.bind(Socket.pack_sockaddr_in(0 , "0.0.0.0"))
		rescue
			# failed to bind, not root?
			raise "failed to create socket: #{$!}"
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
			raise "could not send packet to #{host}: #{$!}"
		end

		# now recieve
		while true do
			loop_time = Time.now

			if (loop_time - start_time) >= timeout
				# timeout afer defined timeout
				@@mutex.synchronize {
					@@seqs.delete(seq)
				}
				return false
			end

			# try to read data
			sel = select([sock],nil,nil,0.1)

			# loop around again if there is no data
			next if sel == nil
			loop_time = Time.now

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
					rtt = sprintf("%.0f", (loop_time - start_time) * 1000)
					@@mutex.synchronize {
						@@seqs.delete(seq)
					}
					return rtt
				end
			end
		end
	end
end

