#
# Author:: John Bellone (<jbellone@bloomberg.net>)
# Copyright:: Copyright (c) 2014 Bloomberg Finance L.P.
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
#

require 'chef/knife/server_bootstrap_base'

class Chef
  class Knife
    class ServerBootstrapOpenstack < Knife

      banner "knife server bootstrap openstack (options)"

      include Knife::ServerBootstrapBase

      deps do
        require 'knife/server/ssh'
        require 'knife/server/credentials'

        begin
          require 'chef/knife/openstack_server_create'
          require 'fog'
          Chef::Knife::OpenstackServerCreate.load_deps

          current_options = self.options
          self.options = Chef::Knife::OpenstackServerCreate.options.dup
          self.options.merge!(current_options)
        rescue LoadError => ex
          ui.error [
            "Knife plugin knife-openstack could not be loaded.",
            "Please add the knife-openstack gem to your Gemfile or",
            "install the gem manually with `gem install knife-openstack'.",
            "(#{ex.message})"
          ].join(" ")
          exit 1
        end
      end

      def run
        validate!
        openstack_bootstrap.run
        fetch_validation_key
        create_root_client
        install_client_key
      end

      def openstack_bootstrap
        ENV['WEBUI_PASSWORD'] = config_val(:webui_password)
        ENV['AMQP_PASSWORD'] = config_val(:amqp_password)
        ENV['NO_TEST'] = "1" if config[:no_test]
        bootstrap = Chef::Knife::OpenstackServerCreate.new
        Chef::Knife::OpenstackServerCreate.options.keys.each do |attr|
          value = config_val(attr)
          bootstrap.config[attr] = value unless ((value.is_a?(Array) and value[1].nil?) or value.nil?)
        end
        bootstrap.config[:distro] = bootstrap_distro
        bootstrap
      end

      def openstack_connection
        @openstack_connection ||= Fog::Compute.new(
          :provider => :openstack,
          :openstack_username => config_val(:openstack_username),
          :openstack_password => config_val(:openstack_password),
          :openstack_auth_url => config_val(:openstack_auth_url),
          :openstack_tenant => config_val(:openstack_tenant),
          :openstack_region => config_val(:openstack_region)
        )
      end

      def server_ip_address
        server = openstack_connection.servers.find do |s|
          s.status == 1 && s.name == config_val(:openstack_node_name)
        end

        server && server.public_ip_address
      end

      private

      def validate!
        if config[:chef_node_name].nil?
          ui.error "You did not provide a valid --node-name value."
          exit 1
        end
        if config_val(:platform) == "auto"
          ui.error "Auto platform mode cannot be used with knife-openstack plugin"
          exit 1
        end
      end

      def ssh_connection
        opts = {
          :host     => server_ip_address,
          :user     => config_val(:ssh_user),
          :port     => config_val(:ssh_port),
          :keys     => [config_val(:identity_file)].compact,
          :password => config_val(:ssh_password)
        }
        if config_val(:host_key_verify) == false
          opts[:user_known_hosts_file] = "/dev/null"
          opts[:paranoid] = false
        end

        ::Knife::Server::SSH.new(opts)
      end
    end
  end
end
