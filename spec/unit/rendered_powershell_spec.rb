require 'spec_helper'
require 'fileutils'
require 'set'

# Renders every piece of PowerShell the module can send to a node: each Exec
# command / unless / onlyif run by the `powershell` provider, and each
# concat fragment landing in a profile. The catalogue specs only check that
# these compile; nothing else ever reads the generated PowerShell.
#
# With WPS_RENDER_DIR set, the snippets are also written to that directory as
# .ps1 files, one per snippet, so tools/Test-RenderedPowerShell.ps1 can parse
# them with the real PowerShell parsers and run PSScriptAnalyzer over them
# (see TESTING.md). The CI `powershell` jobs do exactly that.
#
# Without it, the examples still guard the rendering itself and the coverage of
# the templates/ directory, so a new template cannot ship without a scenario.
describe 'windowspowershell', type: :class do
  render_dir = ENV.fetch('WPS_RENDER_DIR', nil)
  templates  = Dir[File.expand_path('../../templates/*.epp', __dir__)].map { |t| File.basename(t) }

  # `root` is where the Windows runtime smoke test (tools/Test-WindowsRuntime.ps1)
  # expects the module tree; keep both in sync.
  runtime_root = 'C:\\wps-ci\\Modules'

  scenarios = {
    'in_house_module' => <<~PUPPET,
      windowspowershell::module { 'Acme':
        version     => '2.5.1',
        author      => 'A. Dev',
        companyname => 'Example Corp',
        source      => 'puppet:///modules/profile/acme/functions',
      }
      windowspowershell::module { 'Plain': purge_versions => false }
      windowspowershell::module { 'Acme[Beta]': import_in_profile => false }
      windowspowershell::script { 'Get-Greeting':
        modulename => 'Plain',
        content    => "function Get-Greeting { 'hello' }\\n",
      }
    PUPPET
    'external_from_repository' => <<~PUPPET,
      windowspowershell::external_module { 'Pinned':
        ensure            => '2.1.0',
        repository        => 'PSGallery',
        import_in_profile => true,
      }
      windowspowershell::external_module { 'ShortPin': ensure => '2', repository => 'PSGallery' }
      windowspowershell::external_module { 'FourPartPin': ensure => '2.2.1.5', repository => 'PSGallery' }
      windowspowershell::external_module { 'Latest': ensure => present, repository => 'PSGallery' }
      windowspowershell::external_module { 'Bracket[Beta]': ensure => '1.0.0', repository => 'PSGallery' }
      windowspowershell::external_module { 'Gone': ensure => absent }
    PUPPET
    'external_from_source' => <<~PUPPET,
      windowspowershell::external_module { 'Copied':
        ensure            => '3.0.1',
        source            => 'puppet:///modules/profile/copied',
        import_in_profile => false,
      }
    PUPPET
    'proxy' => <<~PUPPET,
      windowspowershell::external_module { 'Proxied': ensure => '1.2.3', repository => 'PSGallery' }
    PUPPET
    'proxy_credential' => <<~PUPPET,
      windowspowershell::external_module { 'Proxied': ensure => '1.2.3', repository => 'PSGallery' }
    PUPPET
    # Fixed layout for the Windows runtime smoke test: it builds this tree on a
    # real node and runs the rendered scripts against it. Repository-backed modules stay
    # out of this scenario (issue #85): Install-Module -Scope AllUsers ignores the custom
    # runtime root, so they are covered by external_from_repository instead.
    'runtime' => <<~PUPPET,
      windowspowershell::module { 'WpsSmoke': version => '1.4', author => 'CI', companyname => 'CI', import_in_profile => false }
      windowspowershell::external_module { 'WpsPinned':
        ensure            => '2.1.0',
        source            => 'puppet:///modules/profile/pinned',
        import_in_profile => false,
      }
      windowspowershell::external_module { 'WpsFloating': ensure => '1.0.0', source => 'puppet:///modules/profile/floating' }
      windowspowershell::external_module { 'WpsGone': ensure => absent }
    PUPPET
  }

  # Parameters of the `windowspowershell` class itself, per scenario.
  class_params = {
    'in_house_module' => { 'manage_pwsh_profile' => true },
    'external_from_repository' => { 'manage_pwsh_profile' => true },
    'external_from_source' => { 'manage_profiles' => false },
    'proxy' => { 'proxy' => 'http://proxy.example.com:3128' },
    'proxy_credential' => {
      'proxy'            => 'http://proxy.example.com:3128',
      'proxy_credential' => { 'username' => 'svc-proxy', 'password' => 'not-a-real-secret' },
    },
    'runtime' => { 'module_root' => runtime_root, 'manage_pwsh_profile' => false },
  }

  powershell7_facts = { 'powershell7' => { 'installed' => true, 'path' => 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' } }
  windows_facts = on_supported_os.select { |name, _| name.include?('2022') }.values.first || on_supported_os.values.first

  used_templates = Set.new
  ran = 0

  # Needs the state of every scenario, so it can only run after all of them.
  after(:all) do # rubocop:disable RSpec/BeforeAfterAll
    # Only meaningful once every scenario ran (not with `rspec -e`).
    next unless ran == scenarios.size

    unused = templates - used_templates.to_a
    raise "templates never rendered by any scenario of #{File.basename(__FILE__)}: #{unused.join(', ')}. Add one." unless unused.empty?
  end

  def powershell_snippets
    catalogue.resources.flat_map do |resource|
      case resource.type
      when 'Exec'
        next [] unless resource[:provider].to_s == 'powershell'

        %i[command unless onlyif].filter_map do |attr|
          value = Array(resource[attr]).join("\n")
          ["#{resource.title} (#{attr})", value] unless value.empty?
        end
      when 'Concat::Fragment'
        next [] unless resource[:target].to_s.end_with?('.ps1')

        [["#{resource.title} (fragment)", resource[:content].to_s]]
      else
        []
      end
    end
  end

  scenarios.each do |scenario, puppet_code|
    context "scenario #{scenario}" do
      let(:facts) { windows_facts.merge(powershell7_facts) }
      let(:pre_condition) { puppet_code }
      let(:params) do
        class_params.fetch(scenario).transform_values do |value|
          next value unless value.is_a?(Hash) && value.key?('password')

          value.merge('password' => sensitive(value['password']))
        end
      end

      before do
        allow(Puppet::Pops::Evaluator::EppEvaluator).to receive(:epp).and_wrap_original do |original, *args|
          used_templates << File.basename(args[1].to_s)
          original.call(*args)
        end
      end

      after { ran += 1 }

      it { is_expected.to compile.with_all_deps }

      it 'renders PowerShell with no template residue' do
        snippets = powershell_snippets
        expect(snippets).not_to be_empty
        snippets.each do |label, content|
          expect(content).not_to match(%r{<%|%>}), "#{label}: unrendered EPP tag"
          expect(content).not_to match(%r{\bundef\b}i), "#{label}: undef leaked into the script"
          expect(content).not_to be_empty, label
        end
      end

      next unless render_dir

      it "writes the snippets to #{render_dir}" do
        target = File.join(render_dir, scenario)
        FileUtils.rm_rf(target)
        FileUtils.mkdir_p(target)
        powershell_snippets.each_with_index do |(label, content), index|
          slug = label.gsub(%r{[^A-Za-z0-9._-]+}, '_').gsub(%r{_+}, '_')
          File.write(File.join(target, format('%<n>02d_%<slug>s.ps1', n: index, slug: slug)), "#{content}\n", encoding: 'UTF-8')
        end
      end
    end
  end
end
