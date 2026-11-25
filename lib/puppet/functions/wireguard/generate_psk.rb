# frozen_string_literal: true

require 'base64'
require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'

# @summary Generate and persist a WireGuard preshared key for a pair of peers.
Puppet::Functions.create_function(:'wireguard::generate_psk') do
  # @param peer_a Stable identifier for one endpoint, including its interface.
  # @param peer_b Stable identifier for the other endpoint, including its interface.
  # @param directory Dedicated absolute directory on the compiler for storing keys.
  # @return [String] Base64-encoded 32-byte preshared key.
  dispatch :generate_psk do
    param 'String[1]', :peer_a
    param 'String[1]', :peer_b
    optional_param 'String[1]', :directory
    return_type 'String'
  end

  def generate_psk(peer_a, peer_b, directory = File.join(Puppet[:vardir], 'wireguard_psks'))
    raise Puppet::Error, 'wireguard::generate_psk: directory must be an absolute path' unless directory.start_with?(File::SEPARATOR)

    FileUtils.mkdir_p(directory, mode: 0o700)
    File.chmod(0o700, directory)
    identifier = Digest::SHA256.hexdigest(JSON.generate([peer_a, peer_b].sort))
    key_path = File.join(directory, "#{identifier}.psk")

    File.open(key_path, File::RDWR | File::CREAT, 0o600) do |key_file|
      key_file.flock(File::LOCK_EX)
      key_file.chmod(0o600)
      key = key_file.read

      if key.empty?
        key = Base64.strict_encode64(SecureRandom.random_bytes(32))
        key_file.write(key)
        key_file.flush
        key_file.fsync
      end

      valid_key = key.match?(%r{\A[A-Za-z0-9+/]{43}=\z}) && Base64.strict_decode64(key).bytesize == 32
      raise Puppet::Error, 'wireguard::generate_psk: stored preshared key is invalid; restore it from backup' unless valid_key

      key
    end
  end
end
