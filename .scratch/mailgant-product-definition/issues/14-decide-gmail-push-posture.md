# Decide Gmail Push Posture Under Device-First

Type: grilling
Status: open
Blocked by: 03

## Question

Given that Gmail real-time push requires Cloud Pub/Sub and a renewing `users.watch`, while MailGant forbids a cloud that reads mailbox content, should v1 be polling/history-sync only, or allow a content-blind push relay that receives only `emailAddress`/`historyId` and never message bodies?
