project_root = File.join(File.dirname(__FILE__), '..')
require File.join(project_root, 'lib', 'bosh_loggalyzer')

describe BoshLoggalyzer do
  it "should find create_vm timings" do
    log_file = File.join(project_root, 'spec', 'fixtures', 'fixture.log')
    loggalyzer = BoshLoggalyzer.new(log_file: log_file)
    result = loggalyzer.loggalyze_create_vm
    first_vm_creation = result.first
    expect(first_vm_creation.instance_name).to eq("compilation-e72d1fec-8995-42ab-b96a-d52705870a2e")
    expect(first_vm_creation.instance_guid).to eq("1ebcff06-56f4-4fd5-adce-03246d00c46f")
    expect(first_vm_creation.vm_guid).to eq("vm-8e35021f-af04-4840-a088-2a0e86a8e4c9")
    expect(first_vm_creation.cpi_total_seconds_elapsed).to eq(17.27)
    expect(first_vm_creation.cpi_logged_seconds_elapsed).to eq(17.27)


  end
end