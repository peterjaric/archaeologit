# Archaeologit
This script scans the history of a user's GitHub repositories
for a given pattern to find sensitive things that may have been there
but have been overwritten in a later commit. For example passwords or secret tokens.

## Usage
	archaeologit.sh <github username or git repo url> '<regular expression to search for>' [<log file>]

## Examples
	archaeologit.sh USERNAME 'password.....|secret.....|passwd.....|credentials.....|creds.....|aws.?key.....|consumer.?key.....|api.?key.....|aws.?token.....|oauth.?token.....|access.?token.....|api.?token.....'
	archaeologit.sh peterjaric 'password|secret|token' scan.log

## Example output
![Example output when running archaeologit](example_output.png)
