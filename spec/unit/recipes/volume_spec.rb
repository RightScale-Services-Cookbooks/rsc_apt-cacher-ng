#
# Cookbook Name:: rsc_apt-cacher-ng
# Spec:: default
#
# Copyright (C) 2015 RightScale, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# The server usage method. It should either be 'dedicated' or 'shared'. In a 'dedicated' server, all
# resources are dedicated to MySQL. In a 'shared' server, MySQL utilizes only half of the server resources.
#

require 'spec_helper'

describe 'apt-cacher-ng::volume' do
  let(:chef_runner) do
    ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '14.04') do |node|
      node.set['cloud']['private_ips'] = ['10.0.2.15']
      node.set['memory']['total'] = '1011228kB'
      node.set['rightscale_volume']['data_storage']['device'] = '/dev/sda'
      node.set['rightscale_backup']['data_storage']['devices'] = ['/dev/sda']
      node.set['apt-cacher-ng']['backup']['lineage'] = 'testing'
    end
  end
  let(:nickname) { chef_run.node['apt-cacher-ng']['device']['nickname'] }
  let(:cache_dir) { chef_run.node['apt-cacher-ng']['cache']['dir'] }
  let(:detach_timeout) do
    chef_runner.converge(described_recipe).node['apt-cacher-ng']['device']['detach_timeout'].to_i
  end

  before do
    stub_command('[ `rs_config --get decommission_timeout` -eq 300 ]').and_return(false)
  end

  context 'apt-cacher-ng/restore/lineage is not set' do
    let(:chef_run) { chef_runner.converge(described_recipe) }

    it 'sets the decommission timeout' do
      expect(chef_run).to run_execute("set decommission timeout to #{detach_timeout}").with(
        command: "rs_config --set decommission_timeout #{detach_timeout}",
      )
    end

    it 'creates a new volume and attaches it' do
      expect(chef_run).to create_rightscale_volume(nickname).with(
        size: 10,
        options: {},
      )
      expect(chef_run).to attach_rightscale_volume(nickname)
    end

    it 'formats the volume and mounts it' do
      expect(chef_run).to create_filesystem(nickname).with(
        fstype: 'ext4',
        mkfs_options: '-F',
        mount: '/mnt/storage',
      )
      expect(chef_run).to enable_filesystem(nickname)
      expect(chef_run).to mount_filesystem(nickname)
    end

    it 'creates the apt-cacher-ng directory on the volume' do
      expect(chef_run).to create_directory('/mnt/storage/apt-cacher-ng')
    end

    it 'deletes the old cache directory' do
      expect(chef_run).to delete_directory(cache_dir).with(
        recursive: true,
      )
    end

    it 'creates the cache directory symlink' do
      expect(chef_run).to create_link(cache_dir).with(
        to: '/mnt/storage/apt-cacher-ng',
      )
    end
    
    context 'iops is set to 100' do
      let(:chef_run) do
        chef_runner.node.set['apt-cacher-ng']['device']['iops'] = 100
        chef_runner.converge(described_recipe)
      end

      it 'creates a new volume with iops set to 100 and attaches it' do
        expect(chef_run).to create_rightscale_volume(nickname).with(
          size: 10,
          options: {iops: 100},
        )
        expect(chef_run).to attach_rightscale_volume(nickname)
      end
    end
  end

  context 'rs-mysql/restore/lineage is set' do
    let(:chef_runner_restore) do
      chef_runner.node.set['apt-cacher-ng']['restore']['lineage'] = 'testing'
      chef_runner
    end
    let(:chef_run) do
      chef_runner_restore.converge(described_recipe)
    end
    let(:device) { chef_run.node['rightscale_volume'][nickname]['device'] }

    it 'creates a volume from the backup' do
      expect(chef_run).to restore_rightscale_backup(nickname).with(
        lineage: 'testing',
        timestamp: nil,
        size: 10,
        options: {},
      )
    end

    it 'mounts and enables the restored volume' do
      expect(chef_run).to mount_mount(device).with(
        fstype: 'ext4',
      )
      expect(chef_run).to enable_mount(device)
    end

    
    it 'creates the apt-cacher-ng directory on the volume' do
      expect(chef_run).to create_directory('/mnt/storage/apt-cacher-ng')
    end
    
    it 'deletes the old cache directory' do
      expect(chef_run).to delete_directory(cache_dir).with(
        recursive: true,
      )
    end

    it 'creates the cache directory symlink' do
      expect(chef_run).to create_link(cache_dir).with(
        to: '/mnt/storage/apt-cacher-ng',
      )
    end

    context 'iops is set to 100' do
      let(:chef_run) do
        chef_runner_restore.node.set['apt-cacher-ng']['device']['iops'] = 100
        chef_runner_restore.converge(described_recipe)
      end

      it 'creates a volume from the backup with iops' do
        expect(chef_run).to restore_rightscale_backup(nickname).with(
          lineage: 'testing',
          timestamp: nil,
          size: 10,
          options: {iops: 100},
        )
      end
    end

    context 'timestamp is set' do
      let(:timestamp) { Time.now.to_i }
      let(:chef_run) do
        chef_runner_restore.node.set['apt-cacher-ng']['restore']['timestamp'] = timestamp
        chef_runner_restore.converge(described_recipe)
      end

      it 'creates a volume from the backup with the timestamp' do
        expect(chef_run).to restore_rightscale_backup(nickname).with(
          lineage: 'testing',
          timestamp: timestamp,
          size: 10,
          options: {},
        )
      end
    end
  end
end
