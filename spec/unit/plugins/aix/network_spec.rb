#
# Author:: Prabhu Das (<prabhu.das@clogeny.com>)
# Copyright:: Copyright (c) 2013 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require File.expand_path(File.dirname(__FILE__) + '/../../../spec_helper.rb')

describe Ohai::System, "AIX network plugin" do

  before(:each) do
    @netstat_rn_grep_default = <<-NETSTAT_RN_GREP_DEFAULT
default            172.31.8.1        UG        2    121789 en0      -      -
NETSTAT_RN_GREP_DEFAULT

    @lsdev_Cc_if = <<-LSDEV_CC_IF
en0 Available  Standard Ethernet Network Interface
LSDEV_CC_IF

    @ifconfig_en0 = <<-IFCONFIG_EN0
en0: flags=1e080863,480<UP,BROADCAST,NOTRAILERS,RUNNING,SIMPLEX,MULTICAST,GROUPRT,64BIT,CHECKSUM_OFFLOAD(ACTIVE),CHAIN> metric 1
        inet 172.29.174.58 netmask 0xffffc000 broadcast 172.29.191.255
        inet 172.29.174.59 broadcast 172.29.191.255
        inet 172.29.174.60 netmask 0xffffc000 broadcast 172.29.191.255
        inet6 ::1%1/0
     tcp_sendspace 262144 tcp_recvspace 262144 rfc1323 1
IFCONFIG_EN0

    @netstat_nrf_inet = <<-NETSTAT_NRF_INET
Destination        Gateway           Flags   Refs     Use  If   Exp  Groups
Route Tree for Protocol Family 2 (Internet):
default            172.29.128.13     UG        0    587683 en0      -      -
172.29.128.0       172.29.174.58     UHSb      0         0 en0      -      -   =>
172.29.128/18      172.29.174.58     U         7   1035485 en0      -      -
172.29.191.255     172.29.174.58     UHSb      0         1 en0      -      -
NETSTAT_NRF_INET

    @aix_arp_an = <<-ARP_AN
  ? (172.29.131.16) at 6e:87:70:0:40:3 [ethernet] stored in bucket 16

  ? (10.153.50.202) at 34:40:b5:ab:fb:5a [ethernet] stored in bucket 40

  ? (10.153.1.99) at 52:54:0:8e:f2:fb [ethernet] stored in bucket 58

  ? (172.29.132.250) at 34:40:b5:a5:d7:1e [ethernet] stored in bucket 59

  ? (172.29.132.253) at 34:40:b5:a5:d7:2a [ethernet] stored in bucket 62

  ? (172.29.128.13) at 60:73:5c:69:42:44 [ethernet] stored in bucket 139

bucket:    0     contains:    0 entries
There are 6 entries in the arp table.
ARP_AN

    @plugin = get_plugin("aix/network")
    @plugin.stub(:collect_os).and_return(:aix)
    @plugin[:network] = Mash.new
    @plugin.stub(:shell_out).with("netstat -rn |grep default").and_return(mock_shell_out(0, @netstat_rn_grep_default, nil))
    @plugin.stub(:shell_out).with("lsdev -Cc if").and_return(mock_shell_out(0, @lsdev_Cc_if, nil))
    @plugin.stub(:shell_out).with("ifconfig en0").and_return(mock_shell_out(0, @ifconfig_en0, nil))
    @plugin.stub(:shell_out).with("entstat -d en0 | grep \"Hardware Address\"").and_return(mock_shell_out(0, "Hardware Address: be:42:80:00:b0:05", nil))
    @plugin.stub(:shell_out).with("netstat -nrf inet").and_return(mock_shell_out(0, @netstat_nrf_inet, nil))
    @plugin.stub(:shell_out).with("netstat -nrf inet6").and_return(mock_shell_out(0, "::1%1  ::1%1  UH 1 109392 en0  -  -", nil))
    @plugin.stub(:shell_out).with("arp -an").and_return(mock_shell_out(0, @aix_arp_an, nil))
  end

  describe "run" do
    before do
      @plugin.run
    end

    it "detects network information" do
      @plugin['network'].should_not be_nil
    end

    it "detects the interfaces" do
      @plugin['network']['interfaces'].keys.sort.should == ["en0"]
    end

    it "detects the ip addresses of the interfaces" do
      @plugin['network']['interfaces']['en0']['addresses'].keys.should include('172.29.174.58')
    end
  end

  describe "netstat -rn |grep default" do
    before do
      @plugin.run
    end

    it "returns the default gateway of the system's network" do
      @plugin[:network][:default_gateway].should == '172.31.8.1'
    end

    it "returns the default interface of the system's network" do
      @plugin[:network][:default_interface].should == 'en0'
    end
  end

  describe "lsdev -Cc if" do
    it "detects the state of the interfaces in the system" do
      @plugin.run
      @plugin['network']['interfaces']['en0'][:state].should == "up"
    end

    it "detects the description of the interfaces in the system" do
      @plugin.run
      @plugin['network']['interfaces']['en0'][:description].should == "Standard Ethernet Network Interface"
    end

    describe "ifconfig interface" do
      it "detects the CHAIN network flag" do
        @plugin.run
        @plugin['network']['interfaces']['en0'][:flags].should include('CHAIN')
      end

      it "detects the metric network flag" do
        @plugin.run
        @plugin['network']['interfaces']['en0'][:metric].should == '1'
      end

      context "inet entries" do
        before do
          @plugin.run
          @inet_entry = @plugin['network']['interfaces']['en0'][:addresses]["172.29.174.58"]
        end

        it "detects the family" do
          @inet_entry[:family].should == 'inet'
        end

        it "detects the netmask" do
          @inet_entry[:netmask].should == '255.255.192.0'
        end

        it "detects the broadcast" do
          @inet_entry[:broadcast].should == '172.29.191.255'
        end

        it "detects all key-values" do
          @plugin['network']['interfaces']['en0'][:tcp_sendspace].should == "262144"
          @plugin['network']['interfaces']['en0'][:tcp_recvspace].should == "262144"
          @plugin['network']['interfaces']['en0'][:rfc1323].should == "1"
        end

        # For an output with no netmask like inet 172.29.174.59 broadcast 172.29.191.255
        context "with no netmask in the output" do
          before do
            @plugin.stub(:shell_out).with("ifconfig en0").and_return(mock_shell_out(0, "inet 172.29.174.59 broadcast 172.29.191.255", nil))
          end

          it "detects the default prefixlen" do
            @inet_entry = @plugin['network']['interfaces']['en0'][:addresses]["172.29.174.59"]
            @inet_entry[:prefixlen].should == '32'
          end

          it "detects the default netmask" do
            @inet_entry = @plugin['network']['interfaces']['en0'][:addresses]["172.29.174.59"]
            @inet_entry[:netmask].should == '255.255.255.255'
          end
        end
      end

      context "inet6 entries" do
        before do
          @plugin.stub(:shell_out).with("ifconfig en0").and_return(mock_shell_out(0, "inet6 ::1%1/0", nil))
          @plugin.run
          @inet_entry = @plugin['network']['interfaces']['en0'][:addresses]["::1"]
        end

        it "detects the prefixlen" do
          @inet_entry[:prefixlen].should == '0'
        end

        it "detects the family" do
          @inet_entry[:family].should == 'inet6'
        end
      end
    end

    context "entstat -d interface" do
      before do
        @plugin.run
        @inet_interface_addresses = @plugin['network']['interfaces']['en0'][:addresses]["BE:42:80:00:B0:05"]
      end
      it "detects the family" do
        @inet_interface_addresses[:family].should == 'lladdr'
      end
    end
  end

  describe "netstat -nrf family" do
    before do
      @plugin.run
    end

    context "inet" do
      it "detects the route destinations" do
        @plugin['network']['interfaces']['en0'][:routes][0][:destination].should == "default"
        @plugin['network']['interfaces']['en0'][:routes][1][:destination].should == "172.29.128.0"
      end

      it "detects the route family" do
        @plugin['network']['interfaces']['en0'][:routes][0][:family].should == "inet"
      end

      it "detects the route gateway" do
        @plugin['network']['interfaces']['en0'][:routes][0][:via].should == "172.29.128.13"
      end

      it "detects the route flags" do
        @plugin['network']['interfaces']['en0'][:routes][0][:flags].should == "UG"
      end
    end

    context "inet6" do

      it "detects the route destinations" do
        @plugin['network']['interfaces']['en0'][:routes][4][:destination].should == "::1%1"
      end

      it "detects the route family" do
        @plugin['network']['interfaces']['en0'][:routes][4][:family].should == "inet6"
      end

      it "detects the route gateway" do
        @plugin['network']['interfaces']['en0'][:routes][4][:via].should == "::1%1"
      end

      it "detects the route flags" do
        @plugin['network']['interfaces']['en0'][:routes][4][:flags].should == "UH"
      end
    end
  end

  describe "arp -an" do
    before do
      @plugin.run
    end
    it "supresses the hostname entries" do
      @plugin['network']['arp'][0][:remote_host].should == "?"
    end

    it "detects the remote ip entry" do
      @plugin['network']['arp'][0][:remote_ip].should == "172.29.131.16"
    end

    it "detects the remote mac entry" do
      @plugin['network']['arp'][0][:remote_mac].should == "6e:87:70:0:40:3"
    end
  end

  describe "hex_to_dec_netmask method" do
    before do
      @plugin.run
    end
    it "converts a netmask from hexadecimal form to decimal form" do
      @plugin.hex_to_dec_netmask('0xffff0000').should == "255.255.0.0"
    end
  end
end
