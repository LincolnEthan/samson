# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe SecretStorage do
  let(:secret) { create_secret 'production/foo/pod2/hello' }

  describe ".allowed_project_prefixes" do
    it "is all for admin" do
      SecretStorage.allowed_project_prefixes(users(:admin)).must_equal ['global'] + Project.pluck(:permalink).sort
    end

    it "is allowed for project admin" do
      SecretStorage.allowed_project_prefixes(users(:project_admin)).must_equal ['foo']
    end
  end

  describe ".write" do
    let(:attributes) { {value: '111', user_id: users(:admin).id, visible: false, comment: 'comment'} }

    it "writes" do
      secret_key = 'production/foo/pod2/hello'
      SecretStorage.write(secret_key, attributes).must_equal true
      secret = SecretStorage::DbBackend::Secret.find(secret_key)
      secret.value.must_equal '111'
      secret.creator_id.must_equal users(:admin).id
      secret.updater_id.must_equal users(:admin).id
    end

    it "expires keys" do
      SecretStorage.keys
      secret_key = 'production/foo/pod2/hello'
      SecretStorage.write(secret_key, attributes).must_equal true
      SecretStorage.keys.must_equal [secret_key]
    end

    it "refuses to write empty keys" do
      SecretStorage.write('', attributes).must_equal false
    end

    it "refuses to write keys with spaces" do
      SecretStorage.write('  production/foo/pod2/hello', attributes).must_equal false
    end

    it "refuses to write empty values" do
      SecretStorage.write('production/foo/pod2/hello', attributes.merge(value: '   ')).must_equal false
    end

    it "refuses to write keys we will not be able to replace in commands" do
      SecretStorage.write('a"b', attributes).must_equal false
    end
  end

  describe ".parse_secret_key" do
    it "parses parts" do
      SecretStorage.parse_secret_key('marry/had/a/little/lamb').must_equal(
        environment_permalink: "marry",
        project_permalink: "had",
        deploy_group_permalink: "a",
        key: "little/lamb"
      )
    end

    it "ignores missing parts" do
      SecretStorage.parse_secret_key('').must_equal(
        environment_permalink: nil,
        project_permalink: nil,
        deploy_group_permalink: nil,
        key: nil
      )
    end
  end

  describe ".generate_secret_key" do
    it "generates a private key" do
      SecretStorage.generate_secret_key(
        environment_permalink: 'production',
        project_permalink: 'foo',
        deploy_group_permalink: 'bar',
        key: 'snafu'
      ).must_equal("production/foo/bar/snafu")
    end

    it "fails raises when missing keys" do
      assert_raises KeyError do
        SecretStorage.generate_secret_key({})
      end
    end
  end

  describe ".read" do
    it "reads" do
      data = SecretStorage.read(secret.id, include_secret: true)
      data.fetch(:value).must_equal 'MY-SECRET'
    end

    it "does not read secrets by default" do
      data = SecretStorage.read(secret.id)
      refute data.key?(:value)
    end

    it "raises on unknown" do
      assert_raises ActiveRecord::RecordNotFound do
        SecretStorage.read('dfsfsfdsdf')
      end
    end
  end

  describe ".read_multi" do
    it "reads" do
      data = SecretStorage.read_multi([secret.id], include_secret: true)
      data.keys.must_equal [secret.id]
      data[secret.id].fetch(:value).must_equal 'MY-SECRET'
    end

    it "does not read secrets by default" do
      data = SecretStorage.read_multi([secret.id])
      refute data[secret.id].key?(:value)
    end

    it "returns empty for unknown" do
      SecretStorage.read_multi([secret.id, 'dfsfsfdsdf']).keys.must_equal [secret.id]
      SecretStorage.read_multi(['dfsfsfdsdf']).keys.must_equal []
    end
  end

  describe ".delete" do
    it "deletes" do
      SecretStorage.delete(secret.id)
      refute SecretStorage::DbBackend::Secret.exists?(secret.id)
    end

    it "expires keys" do
      SecretStorage.keys
      SecretStorage.delete(secret.id)
      SecretStorage.keys.must_equal []
    end
  end

  describe ".keys" do
    it "lists keys" do
      secret # trigger creation
      SecretStorage.keys.must_equal ['production/foo/pod2/hello']
    end

    it "is cached" do
      SecretStorage.keys
      secret # trigger creation
      SecretStorage.keys.must_equal []
    end
  end
end
