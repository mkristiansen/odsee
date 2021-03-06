# encoding: UTF-8
#
# Cookbook Name:: odsee
# Libraries:: secrets
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

require 'tempfile'
require 'openssl'
require 'digest/sha2'
require 'base64'
require 'fileutils'

# Include hooks to extend with class and instance methods.
#
module Odsee
  # instance methods for Resources
  #
  module SecretsResource
    # A file containing the Direcctory Service Manager password.
    #
    # @param [String] admin_passwd
    #   File to use to store the Direcctory Service Manager password.
    #
    # @return [Odsee::Secrets]
    #
    # @api private
    def admin_passwd(arg = nil)
      set_or_return :admin_passwd, arg,
        kind_of: [Odsee::Secrets, String],
        default:  Odsee::Secrets.new(node[:odsee][:admin_password]).freeze
    end

    # A file containing the DSCC agent password.
    #
    # @param [String] agent_passwd
    #   File to use to store the DSCC agent password.
    #
    # @return [Odsee::Secrets]
    #
    # @api private
    def agent_passwd(arg = nil)
      set_or_return :agent_passwd, arg,
        kind_of: [Odsee::Secrets, String],
        default:  Odsee::Secrets.new(node[:odsee][:agent_password]).freeze
    end

    # A file containing the certificate database password.
    #
    # @param [String] cert_passwd
    #   File to use to store the certificate database password.
    #
    # @return [Odsee::Secrets]
    #
    # @api private
    def cert_passwd(arg = nil)
      set_or_return :cert_passwd, arg,
        kind_of: [Odsee::Secrets, String],
        default:  Odsee::Secrets.new(node[:odsee][:cert_password]).freeze
    end
  end

  # Creates a transient file with sensitive content, usefule when you have an
  # excecutable that reads a password from a file but you do not wish to leave
  # the password on the filesystem. When used in a block parameter the file is
  # written and deleted when the block returns, optionally you can encrypt and
  # decrypt your secret strings with salt, cipher and a splash of obfuscation
  #
  class Secrets
    CIPHER_TYPE = 'aes-256-cbc' unless defined?(CIPHER_TYPE)

    # @!attribute [ro] path
    #   @return [String] path to the Odsee::Secrets file
    attr_reader :path

    # instantiate a Odsee::Secrets object, you need to call `#write` or use
    # use in a block with `#tmp` for it to contain the secret
    #
    # @param [String] secret
    #   the secret to write to the file
    #
    # @return [Odsee::Secrets]
    #
    # @api public
    def initialize(secret)
      @secret  = secret.freeze
      @tmpfile = secret_tmp.freeze
      @path    = @tmpfile
      @lock    = Monitor.new
    end

    # @return [String] string of instance
    # @api public
    def to_s
      @path
    end

    # Check if the file exists and contains the secret
    #
    # @return [TrueClass, FalseClass]
    #   true when the file exists and contains the secret, otherwise false
    #
    # @api public
    def exist?
      @lock.synchronize { valid? }
    end

    # Write the secrets file
    #
    # @return [String]
    #   the path to the file
    #
    # @api public
    def write
      @lock.synchronize { atomic_write(@tmpfile, @secret) unless valid? }
    ensure
      ::File.chmod(00400, @tmpfile)
    end

    # Delete the secrets file
    #
    # @return [undefined]
    #
    # @api public
    def delete
      @lock.synchronize do
        ::File.unlink(@tmpfile) if ::File.exist?(@tmpfile)
      end
    end
    alias_method :del, :delete

    # Creates the secrets file yields to the block, removes the secrets file
    # when the block returns
    #
    # @example
    #   secret.tmp { |file| shell_out!("open_sesame --passwd-file #{file}") }
    #
    # @yield [Block]
    #   invokes the block
    #
    # @yieldreturn [Object]
    #   the result of evaluating the optional block
    #
    # @api public
    def tmp(&_block)
      @lock.synchronize do
        atomic_write(@tmpfile, @secret) unless valid?
        yield @path if block_given?
      end
    ensure
      ::File.unlink(@tmpfile) if ::File.exist?(@tmpfile)
    end

    # Search a text file for a matching string
    #
    # @return [TrueClass, FalseClass]
    #   True if the file is present and a match was found, otherwise returns
    #   false if file does not exist and/or does not contain a match
    #
    # @api public
    def valid?
      return false unless ::File.exist?(@tmpfile)
      ::File.open(@tmpfile, &:readlines).map! do |line|
        return true if line.match(@secret)
      end
      false
    end

    # Define an inspect method
    #
    # @return [String] object inspection
    #
    # @api public
    def inspect
      instance_variables.each_with_object([
        "\n#<#{self.class}:0x#{object_id.to_s(16)}>",
        "\tInstance variables:"
      ]) do |item, result|
        result << "\t\t#{item} = #{instance_variable_get(item)}"
        result
      end.join("\n")
    end

    # Encrypt the given string
    #
    # @param [String] text
    #   the text to encrypt
    # @param [String] passwd
    #   secret passphrase to encrypt with
    #
    # @return [String]
    #   encrypted text, suitable for deciphering with #decrypt
    #
    # @api public
    def encrypt(plaintext, passwd, options = {})
      cipher = new_cipher(:encrypt, passwd, options)
      cipher.iv = iv = cipher.random_iv
      ciphertext = cipher.update(plaintext)
      ciphertext << cipher.final
      Base64.encode64(combine_iv_and_ciphertext(iv, ciphertext))
    end

    # Decrypt the given string, using the key and iv supplied
    #
    # @param [String] encrypted_text
    #   the text to decrypt, probably produced with #decrypt
    # @param [String] passwd
    #   secret passphrase to decrypt with
    #
    # @return [String]
    #   the decrypted plaintext
    #
    # @api public
    def decrypt(ciphertext, passwd, options = {})
      iv_and_ciphertext = Base64.decode64(ciphertext)
      cipher = new_cipher(:decrypt, passwd, options)
      cipher.iv, ciphertext = iv_and_ciphertext(cipher, iv_and_ciphertext)
      plaintext = cipher.update(ciphertext)
      plaintext << cipher.final
      plaintext
    end

    private #   P R O P R I E T À   P R I V A T A   Vietato L'accesso

    # Write to a file atomically. Useful for situations where you don't
    # want other processes or threads to see half-written files.
    #
    # @param [String] file
    #   fill path of the file to write to
    # @param [String] secret
    #   content to write to file
    #
    # @api private
    def atomic_write(file, secret, tmp_dir = Dir.tmpdir)
      tmp_file = Tempfile.new(::File.basename(file), tmp_dir)
      tmp_file.write(secret)
      tmp_file.close

      FileUtils.mv(tmp_file.path, file)
      begin
        ::File.chmod(00400, file)

        # rubocop:disable Lint/HandleExceptions
      rescue Errno::EPERM, Errno::EACCES
        # rubocop:enable Lint/HandleExceptions
        # Changing file ownership/permissions failed
      end
    ensure
      tmp_file.close
      tmp_file.unlink
    end

    # Lock a file for a block so only one process can modify it at a time
    #
    # @param [String] file
    #   fill path of the file to lock
    #
    # @yield [Block]
    #   invokes the block
    #
    # @yieldreturn [Object]
    #   the result of evaluating the optional block
    #
    # @api private
    def lock_file(file, &_block)
      if ::File.exist?(file)
        ::File.open(file, 'r+') do |f|
          begin
            f.flock ::File::LOCK_EX
            yield if block_given?
          ensure
            f.flock ::File::LOCK_UN
          end
        end
      else
        yield if block_given?
      end
    end

    # @return [String] tmp_file
    # @api private
    def secret_tmp(tmp_dir = Dir.tmpdir)
      Tempfile.new(rand(0x100000000).to_s(36), tmp_dir).path.freeze
    end

    protected #      A T T E N Z I O N E   A R E A   P R O T E T T A

    # Create a new cipher machine, with its dials set in the given direction
    #
    # @param [:encrypt, :decrypt]
    #   direction whether to encrypt or decrypt
    # @param [String] pass
    #   secret passphrase to decrypt with
    #
    # @api private
    def new_cipher(direction, passwd, options = {})
      check_platform_can_encrypt!
      cipher = OpenSSL::Cipher::Cipher.new(CIPHER_TYPE)
      case direction
      when :encrypt
        cipher.encrypt
      when :decrypt
        cipher.decrypt
      else
        raise "Bad cipher direction #{direction}"
      end
      cipher.key = encrypt_key(passwd, options)
      cipher
    end

    # prepend the initialization vector to the encoded message
    # @api private
    def combine_iv_and_ciphertext(iv, message)
      message.force_encoding('BINARY') if message.respond_to?(:force_encoding)
      iv.force_encoding('BINARY') if iv.respond_to?(:force_encoding)
      iv + message
    end

    # pull the initialization vector from the front of the encoded message
    # @api private
    def separate_iv_and_ciphertext(cipher, iv_and_ciphertext)
      idx = cipher.iv_len
      [iv_and_ciphertext[0..(idx - 1)], iv_and_ciphertext[idx..-1]]
    end

    # convert the passwd passphrase into the key used for encryption
    # @api private
    def encrypt_key(passwd, _options = {})
      passwd = passwd.to_s
      raise 'Missing encryption password!' if passwd.empty?
      Digest::SHA256.digest(passwd)
    end
  end
end
