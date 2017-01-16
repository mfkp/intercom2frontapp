# Intercom to FrontApp migration script

Paying too much for Intercom?
Want to switch to FrontApp but maintain all that precious conversation history?
This is a simple (written in ~ 2 hours, so it ain't perfect) ruby script to pull your Intercom users and conversations, convert them to FrontApp format, and import them into FrontApp.

Anecdote: I used this script to import tens of thousands of users, and 50k+ messages. It takes a few days to run for this amount of messages, but it works.

This might not perfectly map to your use-case, but it could prove useful as a starting point.

_Please read/understand the script before running, as I am not liable if you mess up your user data somehow._

## Pre-setup
- You'll need to request a Personal Access Token (with extended scopes): [developers.intercom.com/docs/personal-access-tokens](https://developers.intercom.com/docs/personal-access-tokens)
- Get your FrontApp JWT from here: [app.frontapp.com/settings/tools/api](https://app.frontapp.com/settings/tools/api)
- Run a `bundle install` to pull the dependency gems

## Actual Setup
- Check all the settings at the top of the script, add all the required options
    - To get the "Inbox ID" you want to import the messages into, run the script with INBOX_ID set to nil, and it will print a list of your available inbox IDs
- Set the `starting_user_id` and `ending_user_id` for the users you'd like to import
    - Note that this only works with integer IDs, and should match what you've set as the `user_id` field in Intercom
- Modify the `create_user_payload` method to suit your needs (currently set to add user profile link and a "group" for the user)

## Running the script
- `ruby intercom2frontapp.rb`

## Things to note

- You might want to change the parts relating to `phone_number`. It's a long story, but my phone numbers are set in custom attributes instead of the Intercom 'phone' attribute. Just search for `phone_number` and update those references if needed.
- Doesn't actually download and re-upload attachments, but rather just links to the intercom attachment in the imported message. They might get deleted from intercom if you cancel your account, so buyer beware
- Doesn't save intercom author (support agent) history, so they're all imported as a generic support account
- Both APIs are rate-limited, but FrontApp is the bigger bottleneck. You can email them to have them up your rate limit
- Doesn't fail gracefully if you have a poor internet connection and a network request fails, this could use some improvement
