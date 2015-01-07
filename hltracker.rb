# tracker.rb
# author: Bryce Mecum (petridish@gmail.com)

# Simple command-line Hotline tracker interface. Connects to and retrieves the 
# server list from a Hotline tracker

# References:
#   http://codebox.org.uk/etc/hotline_tracker_protocol.txt
#   http://sourceforge.net/projects/hotline/files/Hotline%20Protocol/HLProtocol.doc/


# There are two types of messages that can be sent from the tracker. These can
# come in separate packets or together as one. The first type of message is the
# echoing back of the magic number ("HTRK") and the tracker protocol version
# (either 1, old, or 2, new).

# What comes next will start with information about the server list:

#                      Size (bytes)   Notes
# Message type         2              1 => List of servers
# Message data size    2              Remaining size of the request
# Number of servers    2              
# Number of servers    2              Same as previous (not sure why)

# After the information about the server comes a continuous list of servers,
# where each server has the following information:

#                      Size (bytes)   Notes
# IP address           4 
# Port                 2
# Number of users      2
# <empty>              2              Should always be 0
# Name size            1
# Name                 <size>
# Description size     1
# Description          <size>


require 'socket'
require 'iconv'

# Create a converter using Iconv to convert from MacRoman to UTF-8.
converter = Iconv.new "UTF-8", "MacRoman"

# Handle passing the tracker domain name from the command line
if ARGV.length != 1
  puts "Usage: `tracker hltracker.com"
  exit
end


# Connect to the tracker
s = TCPSocket.new(ARGV[0], 5498)


# Send (1) magic number and (2) protocol version to the tracker
s.write("HTRK\x00\x01")



# States

received_echo = false # HTRK01 back from server

# Keep a state variable around to let us check whether we were cut off from
# reading an entire server record. This will be due to the tracker splitting
# information over multiple packets (due to MTU or other reasons).

incomplete_read = false 

debugging = false


# Server information header
message_size = nil
server_count = nil


# Store the servers we receive and parse. Inside this array are hashes storing
# the relevant information about each server index by symbols (e.g. :ip)

server_list = []


# Store the responses from the server. The BasicSocket::recv() call appends
# the result of its last read to this variable. This is done to handle the case 
# where a server record is split between two packets and we need to receive
# the next bit of data off the wire in order to complete the server record.

response = ""


loop do
  puts ">>> LOOP <<<" if debugging
  
  # Break if we should be done
  if !server_count.nil? && server_list.length == server_count
    puts ">> Looks like we've found all the servers. Stopping" if debugging
    break
  end
  
  # Get the next 1024 bytes off the wire
  response += s.recv 1024
  
  # Reset the incomplete_read variable
  incomplete_read = false
  
  puts ">>> Response is #{response.length} bytes long" if debugging
  
  if !received_echo
    if response.length < 6
      puts ">>> Didn't receive echo (HTRK01) first. Exiting." if debugging
      exit
    else 
      if response[0..5] == "HTRK\x00\x01" then
        received_echo = true
        
        puts ">>> Successfully received HTRK01 echo" if debugging
        puts ">>> There are #{response.length - 6} bytes left to read" if debugging

        response = response[6..(response.length - 1)]
      else
        puts ">>> Never received HTRK01 from server" if debugging
        exit
      end
    end    
  end
  
  if received_echo 
    if response.length >= 8 && response[1] == "\x01"
      puts ">>> There's more to read and it starts with a server information header!" if debugging
      
      # Get message data size
      message_size = response[2].ord * 256 + response[3].ord
      puts ">>> Message size is #{message_size}" if debugging
      
      # Get number of servers in list
      server_count = response[4].ord * 256 + response[5].ord
      puts ">>> Number of servers is #{server_count}" if debugging
      
      # Eat what we just read off the line
      response = response[8..(response.length - 1)]
    end
    
    if response.length > 0
      while response.length > 0
        if response.length >= 4 && !incomplete_read
          ip = [response[0].ord, response[4].ord, response[3].ord, response[4].ord].join(".")
          puts "ip address #{ip}" if debugging
        else
          incomplete_read = true
        end
        
        if response.length >= 6 && !incomplete_read
          port = (response[4].ord * 256 + response[5].ord).to_s
          puts "port #{port}" if debugging
        else
          incomplete_read = true
        end
                
        if response.length >= 8 && !incomplete_read
          nusers = (response[6].ord * 256 + response[7].ord).to_s
          puts "nusers #{nusers}" if debugging
        else
          incomplete_read = true
        end
        
        if response.length >= 11 && !incomplete_read
          name_size = response[10].ord
        else
          incomplete_read = true
        end
        
        if response.length >= 11 + name_size && !incomplete_read
          name = converter.iconv response[11..(11 + name_size - 1)]
          puts "name `#{name}'" if debugging
        else
          incomplete_read = true
        end
        
        if response.length >= 11 + name_size + 1 && !incomplete_read
          desc_size = response[11 + name_size].ord
        else
          incomplete_read = true
        end
                
        if response.length >= 11 + name_size + 1 + desc_size && !incomplete_read
          desc = converter.iconv response[(11 + name_size + 1)..(11 + name_size + 1 + desc_size - 1)]
          puts "desc `#{desc}'" if debugging
        else
          incomplete_read = true
        end
                
        if !incomplete_read
          server_list << { 
            :ip => ip,
            :port => port,
            :nusers => nusers,
            :name => name,
            :desc => desc
          }
          
          puts server_list.length if debugging
        end
        
        puts ">>> Incomplete read" if incomplete_read if debugging
        break if incomplete_read
        
        response = response[(11 + name_size + 1 + desc_size)..response.length]
      end
    end
  end
end


# Print the server list
# Print header

print "IP".ljust(21, " ")
print "NAME".ljust(37, " ")
print "USERS".ljust(7, " ")
print "DESCRIPTION".ljust(40, " ")

print "\n"

server_list.each do |s|
  print "#{s[:ip]}:#{s[:port]}".ljust(21, " ") # ip is 15 chrs, port is 5
  print s[:name][0..35].ljust(37, " ")
  print s[:nusers].ljust(7, " ") # nusers is 2bytes but that's huge!
  print s[:desc]
  print "\n"
end