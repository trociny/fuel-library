#    Copyright 2014 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

# VMWare network class for nova-network

class vmware::network::nova (
  $ensure_package = 'present',
  $amqp_port = '5673',
  $nova_network_config = '/etc/nova/nova.conf',
  $nova_network_config_dir = '/etc/nova/nova-network.d'
)
{
  include nova::params

  $nova_network_config_ha = "${nova_network_config_dir}/nova-network-ha.conf"

  if ! defined(File[$nova_network_config_dir]) {
    file { $nova_network_config_dir:
      ensure => directory,
      owner  => nova,
      group  => nova,
      mode   => '0750'
    }
  }

  if ! defined(File[$nova_network_config_ha]) {
    file { $nova_network_config_ha:
      ensure  => present,
      content => template('vmware/nova-network-ha.conf.erb'),
      mode    => '0600',
      owner   => nova,
      group   => nova,
    }
  }


  $nova_user = 'nova'
  $nova_hash = hiera('nova')
  $nova_password = $nova_hash['user_password']
  $management_vip = hiera('management_vip')
  $auth_url = "http://${management_vip}:5000/v2.0"
  $region = hiera('region', 'RegionOne')

  cs_resource { 'p_vcenter_nova_network':
    ensure          => present,
    primitive_class => 'ocf',
    provided_by     => 'fuel',
    primitive_type  => 'nova-network',
    metadata        => {
      resource-stickiness => '1'
    },
    parameters      => {
      amqp_server_port      => $amqp_port,
      user                  => $nova_user,
      password              => $nova_password,
      auth_url              => $auth_url,
      region                => $region,
      config                => $nova_network_config,
      additional_parameters => "--config-file=${nova_network_config_ha}",
    },
    operations      => {
      monitor => {
        interval => '20',
        timeout  => '30',
      },
      start   => {
        timeout => '20',
      },
      stop    => {
        timeout => '20',
      }
    }
  }

  if ($::operatingsystem == 'Ubuntu') {
    tweaks::ubuntu_service_override { 'nova-network':
      package_name => 'nova-network'
    }
  }

  file { 'vcenter-nova-network-ocf':
    path  => '/usr/lib/ocf/resource.d/fuel/nova-network',
    source => 'puppet:///modules/vmware/ocf/nova-network',
    owner => 'root',
    group => 'root',
    mode => '0755',
  }

  service { 'p_vcenter_nova_network':
    ensure => 'running',
    enable => true,
    provider => 'pacemaker',
  }

  package { 'nova-network':
    name   => $::nova::params::network_package_name,
    ensure => present
  }

  service { 'nova-network':
    ensure => 'stopped',
    enable => false,
    name   => $::nova::params::network_service_name,
  }

  anchor { 'vcenter-nova-network-start': }
  anchor { 'vcenter-nova-network-end': }

  Anchor['vcenter-nova-network-start']->
  Package['nova-network']->
  Service['nova-network']->
  File['vcenter-nova-network-ocf']->
  File["${nova_network_config_dir}"]->
  File["${nova_network_config_ha}"]->
  Cs_resource['p_vcenter_nova_network']->
  Service['p_vcenter_nova_network']->
  Anchor['vcenter-nova-network-end']
}
