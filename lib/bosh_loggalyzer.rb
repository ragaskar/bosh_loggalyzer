require 'time'

class BoshLoggalyzer

  class CpiRequest
    def initialize(id:, type:, request_start_time:, request:)
      @type = type
      @request_start_time = request_start_time
      @id = id
      @request = request
      @response = {}
    end

    def total_seconds_elapsed
      (request_end_time.to_f - request_start_time.to_f).round(2)
    end

    def failed?
      response.empty?
    end

    attr_reader :request_start_time, :id, :type, :request
    attr_accessor :process_start_time, :request_end_time, :process_end_time, :response, :logged_seconds
  end

  class CreateVmResult
    require 'json'

    def initialize(instance_guid:, instance_name:, instance_number:, start_time:)
      @instance_guid = instance_guid
      @instance_name = instance_name
      @instance_number = instance_number.to_i
      @start_time = start_time
      @cpi_requests = {}
    end

    attr_reader :instance_guid, :instance_name, :instance_number, :start_time, :cpi_start_time
    attr_writer :cpi_start_time, :cpi_end_time, :last_seen_create_missing_vm_time

    def vm_guid
      create_vm_request = @cpi_requests.values.detect { |request| request.type == "create_vm"}
      if create_vm_request && !create_vm_request.failed?
        create_vm_request.response["result"].first
      else
        "VM creation failed"
      end
    end

    def failed?
      create_vm_request = @cpi_requests.values.detect { |request| request.type == "create_vm"}
      !create_vm_request || create_vm_request.failed?
    end

    def add_cpi_request(cpi_request)
      @cpi_requests[cpi_request.id] = cpi_request
    end

    def get_cpi_request(cpi_request_id)
      @cpi_requests[cpi_request_id]
    end

    def cpi_total_seconds_elapsed
      @cpi_requests.values.sum(&:total_seconds_elapsed).round(2)
    end

    def cpi_logged_seconds_elapsed
      @cpi_requests.values.sum(&:logged_seconds).round(2)
    end

    def cpi_requests
      @cpi_requests.values.sort_by(&:request_start_time)
    end

    def bosh_total_seconds_elapsed
      (@last_seen_create_missing_vm_time.to_i - @start_time.to_i)
    end

    private
  end

  def initialize(log_file:)
    @log_file = log_file
  end

  def loggalyze_create_vm
    vms = {}
    cpi_req_to_instance_guid = {}
    count = 0
    File.open(@log_file, "r").each_line do |line|
      next unless line.match("create_missing_vm") || line.match("req_id") # otherwise we lock up on the TAS manifest log debug output
      if line.match("INFO -- DirectorJobRunner: Creating missing VM\n") #\n is structural -- there is a "Creating missing VMs" string that we will match if it's not there.
        #tested w/ rubular.com against "I, [2022-09-08T18:32:27.824348 #9005] [create_missing_vm(compilation-e72d1fec-8995-42ab-b96a-d52705870a2e/1ebcff06-56f4-4fd5-adce-03246d00c46f (0)/1)]  INFO -- DirectorJobRunner: Creating missing VM"
        _, director_start_timestamp, instance_name, instance_guid, instance_number = line.match(/[^\[]* \[([^\]]*)\] \[create_missing_vm\(([^\/]*)\/([^\s]*) \(([^\)]*)\)[^\]]*\]/).to_a
        vms[instance_guid] = CreateVmResult.new(instance_guid: instance_guid, instance_name: instance_name, instance_number: instance_number, start_time: Time.parse(director_start_timestamp))
      end

      if line.match(/.*\[create_missing_vm.*\[external-cpi\] .* request:.* with command/)
        #tested against D, [2022-09-08T18:32:28.291245 #9005] [create_missing_vm(compilation-e72d1fec-8995-42ab-b96a-d52705870a2e/1ebcff06-56f4-4fd5-adce-03246d00c46f (0)/1)] DEBUG -- DirectorJobRunner: [external-cpi] [cpi-548771] request: {"method":"info","arguments":[],"context":{"director_uuid":"9c2bf459-f8cb-4d98-b174-6b856cf46549","request_id":"cpi-548771","vm":{"stemcell":{"api_version":3}},"datacenters":"<redacted>","default_disk_type":"<redacted>","host":"<redacted>","password":"<redacted>","user":"<redacted>"}} with command: /var/vcap/jobs/vsphere_cpi/bin/cpi
        _, cpi_request_start_timestamp, instance_guid, cpi_req, request_json = line.match(/[^\[]* \[([^\]]*)#\d*\] \[create_missing_vm\([^\/]*\/([^\s]*) \([^\)]*\)[^\]]*\].*\[external-cpi\] \[([^\]]*)\] request:(.*) with command/).to_a
        cpi_req_to_instance_guid[cpi_req] = instance_guid
        result = vms[instance_guid]
        request = {}
        begin
          request = JSON.parse(request_json)
        rescue JSON::ParserError
        end
        if request['method']
          result.add_cpi_request(CpiRequest.new(id: cpi_req, type: request['method'], request_start_time: Time.parse(cpi_request_start_timestamp), request: request))
        end
      end

      if line.match(/.* \[create_missing_vm.*\[external-cpi\] .* response:.*, err:.*/)
        #tested against "D, [2022-09-08T18:32:50.243662 #9005] [create_missing_vm(compilation-e72d1fec-8995-42ab-b96a-d52705870a2e/1ebcff06-56f4-4fd5-adce-03246d00c46f (0)/1)] DEBUG -- DirectorJobRunner: [external-cpi] [cpi-563255] response: {"result":["vm-8e35021f-af04-4840-a088-2a0e86a8e4c9",{"wutang-infrastructure-network":{"type":"manual","ip":"192.168.134.54","netmask":"255.255.128.0","cloud_properties":{"name":"internal-network"},"default":["dns","gateway"],"dns":["10.113.61.110"],"gateway":"192.168.128.1"}}],"error":null,"log":""}, err: I, [2022-09-08T18:32:32.737121 #12794]  INFO -- [req_id cpi-563255]: Starting create_vm..."
        _, cpi_request_end_timestamp, instance_guid, cpi_req, response_json, cpi_process_start_timestamp = line.match(/[^\[]* \[([^\]]*)#\d*\] \[create_missing_vm\([^\/]*\/([^\s]*) \([^\)]*\)[^\]]*\].*\[external-cpi\] \[([^\]]*)\] response:(.*), err:.* [^\[]* \[([^\]]*)#\d*\]/).to_a
        result = vms[instance_guid]
        cpi_request = result.get_cpi_request(cpi_req)
        cpi_request.process_start_time= Time.parse(cpi_process_start_timestamp)
        cpi_request.request_end_time= Time.parse(cpi_request_end_timestamp)
        cpi_request.response = begin; JSON.parse(response_json); rescue JSON::ParserError; {}; end
      end

      if line.match(/.*\[req_id .*\]: Finished .* in .* seconds/)
        #tested against "I, [2022-09-08T18:32:50.004268 #12794]  INFO -- [req_id cpi-563255]: Finished create_vm in 17.27 seconds"
        _, cpi_process_end_timestamp, cpi_req, cpi_logged_time = line.match(/[^\[]* \[([^\]]*)#\d*\].*\[req_id (.*)\]: Finished .* in (\d*\.\d*) seconds/).to_a
        result = vms[cpi_req_to_instance_guid[cpi_req]]
        next unless result #other actions besides "create_missing_vm" can result in CPI calls. We're skipping analyzing these for now.
        cpi_request = result.get_cpi_request(cpi_req)
        cpi_request.process_end_time = Time.parse(cpi_process_end_timestamp)
        cpi_request.logged_seconds = cpi_logged_time.to_f
      end

      if line.match(/\[create_missing_vm\(.*\)\]/)
        #tested against "D, [2022-09-08T18:33:36.303851 #9005] [create_missing_vm(compilation-e72d1fec-8995-42ab-b96a-d52705870a2e/1ebcff06-56f4-4fd5-adce-03246d00c46f (0)/1)] DEBUG -- DirectorJobRunner: Agenda step Bosh::Director::DeploymentPlan::Steps::RenderInstanceJobTemplatesStep finished after 0.000193844s"
        _, director_end_timestamp, instance_guid = line.match(/[^\[]* \[([^\]]*)#\d*\] \[create_missing_vm\([^\/]*\/([^\s]*) \([^\)]*\)[^\]]*\]/).to_a
        next unless vms[instance_guid]
        vms[instance_guid].last_seen_create_missing_vm_time = Time.parse(director_end_timestamp)
      end
    end
    vms.values
  end
end