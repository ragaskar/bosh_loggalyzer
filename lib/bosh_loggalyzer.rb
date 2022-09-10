require 'time'

class BoshLoggalyzer
  class CreateVmResult
    require 'json'
    def initialize(instance_guid:, instance_name:, instance_number:, start_time:)
      @instance_guid = instance_guid
      @instance_name = instance_name
      @instance_number = instance_number
      @start_time = start_time
    end

    attr_reader :instance_guid, :instance_name, :instance_number, :start_time, :cpi_start_time
    attr_writer :cpi_start_time, :result_json, :cpi_end_time
    attr_accessor :cpi_logged_seconds_elapsed

    def vm_guid
      result["result"].first
    end

    def cpi_total_seconds_elapsed
      (@cpi_end_time.to_f - @cpi_start_time.to_f).round(2)
    end

    private

    def result
      @result ||= JSON.parse(@result_json)
    end
  end

  def initialize(log_file:)
    @log_file = log_file
  end

  def loggalyze_create_vm
    vms = {}
    cpi_req_to_instance_guid = {}
    File.open(@log_file, "r").each_line do |line|
      if line.match("INFO -- DirectorJobRunner: Creating missing VM\n") #\n is structural -- there is a "Creating missing VMs" string that we will match if it's not there.
        #tested w/ rubular.com against "I, [2022-09-08T18:32:27.824348 #9005] [create_missing_vm(compilation-e72d1fec-8995-42ab-b96a-d52705870a2e/1ebcff06-56f4-4fd5-adce-03246d00c46f (0)/1)]  INFO -- DirectorJobRunner: Creating missing VM"
        _, director_start_timestamp, instance_name, instance_guid, instance_number = line.match(/[^\[]* \[([^\]]*)\] \[create_missing_vm\(([^\/]*)\/([^\s]*) \(([^\)]*)\)[^\]]*\]/).to_a
        vms[instance_guid] = CreateVmResult.new(instance_guid: instance_guid, instance_name: instance_name, instance_number: instance_number, start_time: Time.parse(director_start_timestamp))
        next
      end
      if line.match("Starting create_vm...\n")
        #tested against "D, [2022-09-08T18:32:50.243662 #9005] [create_missing_vm(compilation-e72d1fec-8995-42ab-b96a-d52705870a2e/1ebcff06-56f4-4fd5-adce-03246d00c46f (0)/1)] DEBUG -- DirectorJobRunner: [external-cpi] [cpi-563255] response: {"result":["vm-8e35021f-af04-4840-a088-2a0e86a8e4c9",{"wutang-infrastructure-network":{"type":"manual","ip":"192.168.134.54","netmask":"255.255.128.0","cloud_properties":{"name":"internal-network"},"default":["dns","gateway"],"dns":["10.113.61.110"],"gateway":"192.168.128.1"}}],"error":null,"log":""}, err: I, [2022-09-08T18:32:32.737121 #12794]  INFO -- [req_id cpi-563255]: Starting create_vm..."
        _, instance_guid, cpi_req, result_json, cpi_start_timestamp = line.match(/[^\[]* \[[^\]]*\] \[create_missing_vm\([^\/]*\/([^\s]*) \([^\)]*\)[^\]]*\].*\[external-cpi\] \[([^\]]*)\] response:(.*), err[^\[]* \[([^\]]*) #\d*\]/).to_a
        cpi_req_to_instance_guid[cpi_req] = instance_guid
        result = vms[instance_guid]
        result.cpi_start_time = Time.parse(cpi_start_timestamp)
        result.result_json = result_json
      end
      if line.match(/Finished create_vm in .* seconds/)
        #tested against I, [2022-09-08T18:32:50.004268 #12794]  INFO -- [req_id cpi-563255]: Finished create_vm in 17.27 seconds
        _, cpi_end_timestamp, cpi_req, cpi_logged_elapsed_time = line.match(/[^\[]* \[([^\]]*)#\d*\].*\[req_id (.*)\]: Finished create_vm in (\d*\.\d*) seconds/).to_a
        result = vms[cpi_req_to_instance_guid[cpi_req]]
        result.cpi_end_time = Time.parse(cpi_end_timestamp)
        result.cpi_logged_seconds_elapsed = cpi_logged_elapsed_time.to_f
      end
    end
    vms.values
  end
end