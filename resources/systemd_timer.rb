#
# Cookbook:: chef-client
# resource:: chef_client_systemd_timer
#
# Copyright:: 2020, Chef Software, Inc.
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

resource_name :chef_client_systemd_timer

property :user, String, default: 'root'

property :job_name, String, default: 'chef-client'
property :delay_after_boot, String, default: '1min'
property :interval, String, default: '30min'

property :accept_chef_license, [true, false], default: false

property :splay, [Integer, String], default: 300,
                                    coerce: proc { |x| Integer(x) },
                                    callbacks: { 'should be a positive number' => proc { |v| v > 0 } }

property :description, String, default: 'Chef Infra Client periodic execution'
property :run_on_battery, [true, false], default: true

property :log_directory, String, default: '/var/log/chef'
property :log_file_name, String, default: 'client.log'
property :chef_binary_path, String, default: '/opt/chef/bin/chef-client'
property :daemon_options, Array, default: []

action :add do
  unless ::Dir.exist?(new_resource.log_directory)
    directory new_resource.log_directory do
      owner new_resource.user
      mode '0640'
      recursive true
    end
  end

  systemd_unit "#{new_resource.job_name}.service" do
    content service_content
    action :create
  end

  systemd_unit "#{new_resource.job_name}.timer" do
    content timer_content
    action [:create, :enable, :start]
  end
end

action :remove do
  systemd_unit "#{new_resource.job_name}.service" do
    action :remove
  end

  systemd_unit "#{new_resource.job_name}.timer" do
    action :remove
  end
end

action_class do
  #
  # The chef-client command to run in the systemd unit.
  #
  # @return [String]
  #
  def chef_client_cmd
    cmd = "#{new_resource.chef_binary_path} "
    cmd << "#{new_resource.daemon_options.join(' ')} " unless new_resource.daemon_options.empty?
    cmd << "-L #{::File.join(new_resource.log_directory, new_resource.log_file_name)}"
    cmd << '--chef-license accept ' if new_resource.accept_chef_license && Gem::Requirement.new('>= 14.12.9').satisfied_by?(Gem::Version.new(Chef::VERSION))
    cmd
  end

  #
  # The timer content to pass to the systemd_unit
  #
  # @return [Hash]
  #
  def timer_content
    {
    'Unit' => { 'Description' => new_resource.description },
    'Timer' => {
      'OnBootSec' => new_resource.delay_after_boot,
      'OnUnitActiveSec' => new_resource.interval,
      'RandomizedDelaySec' => new_resource.splay,
      },
    'Install' => { 'WantedBy' => 'timers.target' },
    }
  end

  #
  # The service content to pass to the systemd_unit
  #
  # @return [Hash]
  #
  def service_content
    unit = {
      'Unit' => {
        'Description' => new_resource.description,
        'After' => 'network.target auditd.service',
      },
      'Service' => {
        'Type' => 'oneshot',
        'ExecStart' => chef_client_cmd,
        'SuccessExitStatus' => 3,
      },
      'Install' => { 'WantedBy' => 'multi-user.target' },
    }

    unit['Service']['ConditionACPower'] = 'true' unless new_resource.run_on_battery

    unit
  end
end