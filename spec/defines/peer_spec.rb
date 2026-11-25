# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'digest'
require 'json'

describe 'wireguard::peer', type: :define do
  let(:key_directory) { Dir.mktmpdir('wireguard-mesh-psks') }
  let(:pre_condition) { 'concat { "/etc/wireguard/wg0.conf": }' }

  before do
    allow(Puppet).to receive(:[]).and_call_original
    allow(Puppet).to receive(:[]).with(:vardir).and_return(key_directory)
  end

  after do
    FileUtils.remove_entry(key_directory)
  end

  [
    ['node-a.example.com', 'node-b.example.com'],
    ['node-b.example.com', 'node-a.example.com'],
  ].each do |local_node, remote_node|
    context "when collected by #{local_node}" do
      let(:title) { "#{remote_node}-wg0-peer" }
      let(:facts) { { networking: { fqdn: local_node, ip: '192.0.2.1' } } }
      let(:params) do
        {
          interface: 'wg0',
          public_key: 'remote-public-key',
          endpoint: "#{remote_node}:51820",
          allowed_ips: ['192.0.2.2'],
          mesh_psk: true,
        }
      end

      it 'uses the collecting agent identity and the same canonical pair on both endpoints' do
        content = catalogue.resource('Concat::Fragment', title)[:content]
        endpoints = ['node-a.example.com-wg0-peer', 'node-b.example.com-wg0-peer']
        identifier = Digest::SHA256.hexdigest(JSON.generate(endpoints.sort))
        key_path = File.join(key_directory, 'wireguard_psks', "#{identifier}.psk")

        expect(File).to exist(key_path)
        expect(content).to include("PresharedKey=#{File.read(key_path)}")
      end
    end
  end
end
