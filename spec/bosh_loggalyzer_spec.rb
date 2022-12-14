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
    expect(first_vm_creation.cpi_total_seconds_elapsed).to eq(31.78)
    expect(first_vm_creation.cpi_logged_seconds_elapsed).to eq(23.54)
    expect(first_vm_creation.bosh_total_seconds_elapsed).to eq(69)
    end

  it "should 'work' even if a create_vm failed" do
    log_file = File.join(project_root, 'spec', 'fixtures', 'failed_create_vm.log')
    loggalyzer = BoshLoggalyzer.new(log_file: log_file)
    result = loggalyzer.loggalyze_create_vm
    failed_vm_create_result = result.detect { | r| r.instance_name == "mysql_proxy" && r.instance_number == 1 }
    expect(failed_vm_create_result.instance_name).to eq("mysql_proxy")
    expect(failed_vm_create_result.instance_guid).to eq("7cdaa6e2-f674-45fa-8dde-4843b4218e24")
    expect(failed_vm_create_result.vm_guid).to eq("VM creation failed")
    expect(failed_vm_create_result.failed?).to be(true)
  end
end