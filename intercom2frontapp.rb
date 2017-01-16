require 'net/http'
require 'json'
require 'intercom'
require 'ruby-progressbar'

##### SETUP OPTIONS BEGINS HERE #####

# intercom personal access token with extended scopes
$intercom = Intercom::Client.new(token: 'INTERCOM_TOKEN_HERE')

# FrontApp JWT
JWT = 'FRONTAPP_JWT_HERE'

# Inbox to import messages into (set as nil to print list of available inbox IDs)
INBOX_ID = nil

# the email that your outbound support messages will be imported as
# example: support@yourdomain.com
OUTBOUND_EMAIL = 'support@yourdomain.com'

# the name that your outbound support messages will be imported as
# example: YourApp Support
OUTBOUND_NAME = 'YourApp Support'

# true to import everyone, false to only import contacts with conversations
IMPORT_ALL_CONTACTS = true

# true to skip one-way admin-initiated outbound messages (like auto-messages with no reply from user)
SKIP_ONE_WAY_MESSAGES = false

# Add optional tags to the imported messages
FRONTAPP_IMPORT_TAGS = ['intercom-import']

# User profile link, will be send in 'links' in frontapp payload
USER_PROFILE_LINK = 'http://yourapp.com/users/' # + append the user_id

# loop through intercom users (based on user_id field)
starting_user_id = 1
ending_user_id = 999

##### END OF CUSTOMIZABLE SETUP OPTIONS #####



if INBOX_ID.nil?
  path = 'inboxes'
  uri = URI.parse(BASE_URI + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  request = Net::HTTP::Get.new(uri.request_uri, initheader = FRONT_HEADERS)
  response = http.request(request)
  resp = JSON.parse(response.body)
  puts 'Available Inbox IDs:'
  resp['_results'].each do |inbox|
    puts "#{inbox['name']}: #{inbox['id']}"
  end
  puts "\nMake sure to set the INBOX_ID to one of these inboxes, then run script again."
  exit
end

if JWT.nil?
  puts 'Please set the FrontApp JWT before running.'
  exit
end

BASE_URI = 'https://api2.frontapp.com/'
FRONT_HEADERS = {
    'Authorization' => "Bearer #{JWT}",
    'Accept' => 'application/json',
    'Content-Type' => 'application/json'
}

$frontapp_rate_limit = {
    remaining: 999,
    reset_timestamp: Time.now.to_i + 30
}

$pb = ProgressBar.create(title: 'Import', starting_at: 0, total: (ending_user_id-starting_user_id+1))

def check_intercom_rate_limit
  rl = $intercom.rate_limit_details
  if rl.any?
    if rl[:remaining] < 10
      $pb.log "Intercom rate limit remaining: #{rl[:remaining].to_s}"
    end
    # not sure if should pause at zero or one, so we'll pause on 1 remaining
    if rl[:remaining] <= 1
      sleep_seconds = (rl[:reset_at].to_i - Time.now.to_i) + 1 # plus one second for good measure
      $pb.log "Sleeping for #{sleep_seconds.to_s} seconds due to Intercom rate limit..."
      sleep(sleep_seconds)
    end
  end
end

def check_frontapp_rate_limit
  # not sure if should pause at zero or one, so we'll pause on 1 remaining
  if $frontapp_rate_limit[:remaining] < 10
    $pb.log "Frontapp rate limit remaining: #{$frontapp_rate_limit[:remaining].to_s}"
  end

  if $frontapp_rate_limit[:remaining] <= 1
    sleep_seconds = ($frontapp_rate_limit[:reset_timestamp].to_i - Time.now.to_i) + 1 # plus one second for good measure
    $pb.log "Sleeping for #{sleep_seconds.to_s} seconds due to FrontApp rate limit..."
    sleep(sleep_seconds)
  end
end

def set_frontapp_rate_limit(response)
  $frontapp_rate_limit[:remaining] = Integer(response['x-ratelimit-remaining'])
  $frontapp_rate_limit[:reset_timestamp] = response['x-ratelimit-reset']
end


def import_contact(full_user)
  email = full_user.email.delete("\s")
  contact_id = "alt:email:#{email}"
  if contact_id_exists?(contact_id)
    update_contact(full_user)
    if full_user.custom_attributes['phone_number'] && full_user.custom_attributes['phone_number'].length > 0
      update_phone(full_user)
    end
  else
    create_contact(full_user)
  end
end

def contact_id_exists?(contact_id)
  check_frontapp_rate_limit
  path = "contacts/#{contact_id}"
  uri = URI.parse(BASE_URI + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  request = Net::HTTP::Get.new(uri.request_uri, initheader = FRONT_HEADERS)
  response = http.request(request)
  set_frontapp_rate_limit(response)

  response.code == '200'
end

def update_contact(full_user)
  check_frontapp_rate_limit
  email = full_user.email.delete("\s")
  contact_id = "alt:email:#{email}"
  path = "contacts/#{contact_id}"
  uri = URI.parse(BASE_URI + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  request = Net::HTTP::Patch.new(uri.request_uri, initheader = FRONT_HEADERS)
  payload = create_user_payload(full_user).to_json
  request.body = payload
  response = http.request(request)
  set_frontapp_rate_limit(response)

  response.code == '204'
end

def update_phone(full_user)
  check_frontapp_rate_limit
  email = full_user.email.delete("\s")
  contact_id = "alt:email:#{email}"
  path = "contacts/#{contact_id}/handles"
  uri = URI.parse(BASE_URI + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  request = Net::HTTP::Post.new(uri.request_uri, initheader = FRONT_HEADERS)
  formatted_phone = '+1' + full_user.custom_attributes['phone_number'].gsub(/[\s()-]/, '')
  payload = {
      handle: formatted_phone,
      source: 'phone'
  }.to_json
  request.body = payload
  response = http.request(request)
  set_frontapp_rate_limit(response)

  response.code == '204'
end

def create_contact(full_user)
  check_frontapp_rate_limit
  path = 'contacts'
  uri = URI.parse(BASE_URI + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  request = Net::HTTP::Post.new(uri.request_uri, initheader = FRONT_HEADERS)
  email = full_user.email.delete("\s")
  handles = [
      {
          handle: email,
          source: 'email'
      }
  ]
  if full_user.custom_attributes['phone_number'] && (full_user.custom_attributes['phone_number'].length > 0)
    formatted_phone = '+1' + full_user.custom_attributes['phone_number'].gsub(/[\s()-]/, '')
    # first make sure phone isn't already registered to a user, because front doesn't like this
    contact_phone_id = "alt:phone:#{formatted_phone}"
    phone_used = contact_id_exists?(contact_phone_id)

    if phone_used
      $pb.log 'Phone already registered, skipping phone: ' + formatted_phone
    else
      handles << {
          handle: formatted_phone,
          source: 'phone'
      }
    end
  end
  payload = create_user_payload(full_user)
  payload[:handles] = handles
  request.body = payload.to_json
  response = http.request(request)
  set_frontapp_rate_limit(response)

  response.code == '201'
end


def create_user_payload(full_user)
  {
      name: full_user.name,
      links: [
          USER_PROFILE_LINK + full_user.custom_attributes['to_param']
      ],
      group_names: [
          full_user.custom_attributes['group']
      ]
  }
end


def create_payload(full_user, full_convo, msg)
  is_inbound = (msg.author.class == Intercom::User)
  email = full_user.email.delete("\s")
  if is_inbound
    # inbound from customer
    sender = {
        handle: email,
        name: full_user.name
    }
    to = OUTBOUND_EMAIL
  else
    # outbound from us
    sender = {
        handle: OUTBOUND_EMAIL,
        name: OUTBOUND_NAME
    }
    to = email
  end

  subject = "Intercom chat with #{full_user.name}"
  orig_msg = full_convo.conversation_message
  if orig_msg.respond_to?(:subject) && orig_msg.subject.length > 0
    # intercom seems to put a paragraph tag around the subject line, weird
    subject = orig_msg.subject.gsub('<p>', '').gsub('</p>', '')
  end

  payload = {
      sender: sender,
      to: [to],
      subject: subject,
      body: msg.body,
      body_format: 'html',
      external_id: msg.id,
      created_at: msg.respond_to?(:created_at) ? msg.created_at.to_i : full_convo.created_at.to_i,
      tags: FRONTAPP_IMPORT_TAGS,
      metadata: {
          thread_ref: full_convo.id,
          is_inbound: is_inbound,
          is_archived: true
      }
  }
  if msg.attachments.any?
    payload[:body] = '' if payload[:body].nil?
    payload[:body] = payload[:body] + '<div>ATTACHMENTS:</div>'
    msg.attachments.each do |attach|
      payload[:body] = payload[:body] + "<div><a href='#{attach['url']}'>#{attach['url']}</a></div>"
    end
  end
  payload
end


def import_message(payload)
  if payload[:body].nil?
    $pb.log 'SKIPPING MESSAGE DUE TO EMPTY BODY'
    return
  end
  check_frontapp_rate_limit
  path = "inboxes/#{INBOX_ID}/imported_messages"
  uri = URI.parse(BASE_URI + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  request = Net::HTTP::Post.new(uri.request_uri, initheader = FRONT_HEADERS)
  request.body = payload.to_json
  response = http.request(request)
  set_frontapp_rate_limit(response)

  succeeded = response.code == '202'
  if succeeded
    # $pb.log "Msg Imported: #{succeeded.to_s} " + JSON.parse(response.body).to_s
  else
    $pb.log "Error Importing Msg: #{succeeded.to_s} " + JSON.parse(response.body).to_s
  end

  succeeded
end


# THIS IS WHERE THE ACTUAL SCRIPT STARTS YO
(starting_user_id..ending_user_id).each do |user_id|
  begin
    check_intercom_rate_limit
    start_time = Time.now.to_i
    full_user = $intercom.users.find(user_id: user_id.to_s)
    email = full_user.email.delete("\s")
    msg = "IMPORTING USER #{user_id}: #{email}"
    if full_user.name && full_user.name.length > 0
      msg += " (#{full_user.name})"
    end
    $pb.log msg
    check_intercom_rate_limit
    convos = $intercom.conversations.find_all(user_id: user_id.to_s, type: 'user')

    if IMPORT_ALL_CONTACTS
      # create a contact in FrontApp, ensuring we have a contact even if they don't have any conversations
      import_contact(full_user)
    end

    total_msgs = 0
    imported_convos = 0
    convos.each do |convo|
      check_intercom_rate_limit
      full_convo = $intercom.conversations.find(id: convo.id)

      # check if it's an outbound message with no replies, if so, skip
      if SKIP_ONE_WAY_MESSAGES &&
          full_convo.conversation_parts.empty? &&
          full_convo.conversation_message.author.class == Intercom::Admin
        next
      end

      imported_convos += 1

      # first do the initial message
      msg = full_convo.conversation_message
      if msg.body && (!msg.body.empty? || msg.attachments.any?)
        begin
          payload = create_payload(full_user, full_convo, msg)
          import_message(payload)
          total_msgs += 1
        rescue Exception => e
          $pb.log 'ERROR'
          $pb.log e.to_s
        end
      end
      # then import any replies
      full_convo.conversation_parts.each do |part|
        # skip the stuff that's not a message (such as "assigning" or "closing")
        if part.part_type == 'comment'
          begin
            payload = create_payload(full_user, full_convo, part)
            import_message(payload)
            total_msgs += 1
          rescue Exception => e
            $pb.log 'ERROR'
            $pb.log e.to_s
          end
        end
      end
    end
    done_time = Time.now.to_i
    msg = "Imported #{imported_convos.to_s} conversations (#{total_msgs} messages)."
    if convos.count > imported_convos
      msg += " Skipped #{(convos.count - imported_convos).to_s} one-way conversations."
    end
    msg += " Total time: #{done_time - start_time} seconds"
    $pb.log msg
  rescue Intercom::ResourceNotFound => e
    # just skip if user_id not found
    $pb.log "User not found with id: #{user_id.to_s}"
  end

  $pb.increment

end
