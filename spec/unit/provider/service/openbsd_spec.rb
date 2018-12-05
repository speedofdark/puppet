require 'spec_helper'

describe 'Puppet::Type::Service::Provider::Openbsd',
         unless: Puppet::Util::Platform.windows? || Puppet::Util::Platform.jruby? do
  let(:provider_class) { Puppet::Type.type(:service).provider(:openbsd) }

  before :each do
    Puppet::Type.type(:service).stubs(:defaultprovider).returns provider_class
    Facter.stubs(:value).with(:operatingsystem).returns :openbsd
    Facter.stubs(:value).with(:osfamily).returns 'OpenBSD'
    FileTest.stubs(:file?).with('/usr/sbin/rcctl').returns true
    FileTest.stubs(:executable?).with('/usr/sbin/rcctl').returns true
  end

  context "#instances" do
    it "should have an instances method" do
      expect(provider_class).to respond_to :instances
    end

    it "should list all available services" do
      provider_class.stubs(:execpipe).with(['/usr/sbin/rcctl', :getall]).yields File.read(my_fixture('rcctl_getall'))
      expect(provider_class.instances.map(&:name)).to eq([
        'accounting', 'pf', 'postgresql', 'tftpd', 'wsmoused', 'xdm',
      ])
    end
  end

  context "#start" do
    it "should use the supplied start command if specified" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :start => '/bin/foo'))
      provider.expects(:execute).with(['/bin/foo'], :failonfail => true, :override_locale => false, :squelch => false, :combine => true)
      provider.start
    end

    it "should start the service otherwise" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider.expects(:texecute).with(:start, ['/usr/sbin/rcctl', '-f', :start, 'sshd'], true)
      provider.start
    end
  end

  context "#stop" do
    it "should use the supplied stop command if specified" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :stop => '/bin/foo'))
      provider.expects(:execute).with(['/bin/foo'], :failonfail => true, :override_locale => false, :squelch => false, :combine => true)
      provider.stop
    end

    it "should stop the service otherwise" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider.expects(:texecute).with(:stop, ['/usr/sbin/rcctl', :stop, 'sshd'], true)
      provider.stop
    end
  end

  context "#status" do
    it "should use the status command from the resource" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :status => '/bin/foo'))
      provider.expects(:execute).with(['/usr/sbin/rcctl', :get, 'sshd', :status], :failonfail => true, :override_locale => false, :squelch => false, :combine => true).never
      provider.expects(:execute).with(['/bin/foo'], :failonfail => false, :override_locale => false, :squelch => false, :combine => true)
      provider.status
    end

    it "should return :stopped when status command returns with a non-zero exitcode" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :status => '/bin/foo'))
      provider.expects(:execute).with(['/usr/sbin/rcctl', :get, 'sshd', :status], :failonfail => true, :override_locale => false, :squelch => false, :combine => true).never
      provider.expects(:execute).with(['/bin/foo'], :failonfail => false, :override_locale => false, :squelch => false, :combine => true)
      $CHILD_STATUS.stubs(:exitstatus).returns 3
      expect(provider.status).to eq(:stopped)
    end

    it "should return :running when status command returns with a zero exitcode" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :status => '/bin/foo'))
      provider.expects(:execute).with(['/usr/sbin/rcctl', :get, 'sshd', :status], :failonfail => true, :override_locale => false, :squelch => false, :combine => true).never
      provider.expects(:execute).with(['/bin/foo'], :failonfail => false, :override_locale => false, :squelch => false, :combine => true)
      $CHILD_STATUS.stubs(:exitstatus).returns 0
      expect(provider.status).to eq(:running)
    end
  end

  context "#restart" do
    it "should use the supplied restart command if specified" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :restart => '/bin/foo'))
      provider.expects(:execute).with(['/usr/sbin/rcctl', '-f', :restart, 'sshd'], :failonfail => true, :override_locale => false, :squelch => false, :combine => true).never
      provider.expects(:execute).with(['/bin/foo'], :failonfail => true, :override_locale => false, :squelch => false, :combine => true)
      provider.restart
    end

    it "should restart the service with rcctl restart if hasrestart is true" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :hasrestart => true))
      provider.expects(:texecute).with(:restart, ['/usr/sbin/rcctl', '-f', :restart, 'sshd'], true)
      provider.restart
    end

    it "should restart the service with rcctl stop/start if hasrestart is false" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :hasrestart => false))
      provider.expects(:texecute).with(:restart, ['/usr/sbin/rcctl', '-f', :restart, 'sshd'], true).never
      provider.expects(:texecute).with(:stop, ['/usr/sbin/rcctl', :stop, 'sshd'], true)
      provider.expects(:texecute).with(:start, ['/usr/sbin/rcctl', '-f', :start, 'sshd'], true)
      provider.restart
    end
  end

  context "#enabled?" do
    it "should return :true if the service is enabled" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:get, 'sshd', :status)
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'get', 'sshd', 'status'], :failonfail => false, :combine => false, :squelch => false).returns(stub(:exitstatus => 0))
      expect(provider.enabled?).to eq(:true)
    end

    it "should return :false if the service is disabled" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:get, 'sshd', :status).returns('NO')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'get', 'sshd', 'status'], :failonfail => false, :combine => false, :squelch => false).returns(stub(:exitstatus => 1))
      expect(provider.enabled?).to eq(:false)
    end
  end

  context "#enable" do
    it "should run rcctl enable to enable the service" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:enable, 'sshd').returns('')
      provider.expects(:rcctl).with(:enable, 'sshd')
      provider.enable
    end

    it "should run rcctl enable with flags if provided" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :flags => '-6'))
      provider_class.stubs(:rcctl).with(:enable, 'sshd').returns('')
      provider_class.stubs(:rcctl).with(:set, 'sshd', :flags, '-6').returns('')
      provider.expects(:rcctl).with(:enable, 'sshd')
      provider.expects(:rcctl).with(:set, 'sshd', :flags, '-6')
      provider.enable
    end
  end

  context "#disable" do
    it "should run rcctl disable to disable the service" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:disable, 'sshd').returns('')
      provider.expects(:rcctl).with(:disable, 'sshd')
      provider.disable
    end
  end

  context "#running?" do
    it "should run rcctl check to check the service" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:check, 'sshd').returns('sshd(ok)')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'check', 'sshd'], :failonfail => false, :combine => false, :squelch => false).returns('sshd(ok)')
      expect(provider.running?).to be_truthy
    end

    it "should return true if the service is running" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:check, 'sshd').returns('sshd(ok)')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'check', 'sshd'], :failonfail => false, :combine => false, :squelch => false).returns('sshd(ok)')
      expect(provider.running?).to be_truthy
    end

    it "should return nil if the service is not running" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:check, 'sshd').returns('sshd(failed)')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'check', 'sshd'], :failonfail => false, :combine => false, :squelch => false).returns('sshd(failed)')
      expect(provider.running?).to be_nil
    end
  end

  context "#flags" do
    it "should return flags when set" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd', :flags => '-6'))
      provider_class.stubs(:rcctl).with('get', 'sshd', 'flags').returns('-6')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'get', 'sshd', 'flags'], :failonfail => false, :combine => false, :squelch => false).returns('-6')
      provider.flags
    end

    it "should return empty flags" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with('get', 'sshd', 'flags').returns('')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'get', 'sshd', 'flags'], :failonfail => false, :combine => false, :squelch => false).returns('')
      provider.flags
    end

    it "should return flags for special services" do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'pf'))
      provider_class.stubs(:rcctl).with('get', 'pf', 'flags').returns('YES')
      provider.expects(:execute).with(['/usr/sbin/rcctl', 'get', 'pf', 'flags'], :failonfail => false, :combine => false, :squelch => false).returns('YES')
      provider.flags
    end
  end

  context "#flags=" do
    it "should run rcctl to set flags", unless: Puppet::Util::Platform.windows? || RUBY_PLATFORM == 'java' do
      provider = provider_class.new(Puppet::Type.type(:service).new(:name => 'sshd'))
      provider_class.stubs(:rcctl).with(:set, 'sshd', :flags, '-4').returns('')
      provider.expects(:rcctl).with(:set, 'sshd', :flags, '-4')
      provider.flags = '-4'
    end
  end
end
