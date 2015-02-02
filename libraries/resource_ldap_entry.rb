# encoding: UTF-8
#
# Cookbook Name:: odsee
# Resources:: ldap_entry
#
# Author:    Stefano Harding <riddopic@gmail.com>
# License:   Apache License, Version 2.0
# Copyright: (C) 2014-2015 Stefano Harding
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

# Creates a user for various kinds of identity management purposes. This is
# useful to create users who can bind (connect) and use the LDAP instance. It
# can also be used to create users with posix attributes on them for use with
# UNIX systems.
#
class Chef::Resource::LdapEntry < Chef::Resource::LWRPBase
  include Odsee

  identity_attr :dn
  provides :ldap_entry, os: 'linux'
  self.resource_name = :ldap_entry

  # Adds actions to the list of valid actions for this resource
  #
  # @return [Chef::Provider::LdapUser]
  # @api public
  actions :create, :delete

  # Set or return the list of `state attributes` implemented by the Resource,
  # these are attributes that describe the desired state of the system
  #
  # @return [Chef::Resource::LdapUser]
  # @api private
  state_attrs :created

  # Sets the default action
  #
  # @return [undefined]
  # @api private
  default_action :create

  # Creates the namespaced Chef::Provider::LdapUser
  #
  # @return [undefined]
  # @api private
  provider_base Chef::Provider::LdapEntry

  attribute :dn,                 kind_of:  String,        name_attribute: true
  attribute :attributes,         kind_of:  Hash,          default: {}
  attribute :append_attributes,  kind_of:  Hash,          default: {}
  attribute :seed_attributes,    kind_of:  Hash,          default: {}
  attribute :prune,              kind_of: [Array, Hash],  default: []
  attribute :host,               kind_of:  String,        default: 'localhost'
  attribute :port,               kind_of:  Integer,       default: 389
  attribute :credentials,        kind_of: [String, Hash], default: 'default_credentials'
  attribute :databag_name,       kind_of:  String
end
