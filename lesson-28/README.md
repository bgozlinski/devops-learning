# Lesson 28 - AWS cloud technologies (part 1)

First contact with AWS: an IAM structure that stops the account from being run as root, a cost
budget that shouts before the bill does, and the CLI operations from homework 2. Everything is a
script, so the whole thing can be re-run, re-read and torn down.

| What | Where |
|---|---|
| Shared settings | [`config.sh`](config.sh) - region, email, budget limit, resource names |
| Helper functions | [`scripts/lib.sh`](scripts/lib.sh) - logging, idempotency checks, evidence capture |
| Custom IAM policy | [`policies/developer-policy.json`](policies/developer-policy.json) |
| Homework 1 - IAM | [`scripts/01-iam-structure.sh`](scripts/01-iam-structure.sh) |
| Homework 1 - budget | [`scripts/02-budget-alert.sh`](scripts/02-budget-alert.sh) |
| Homework 2 - S3 | [`scripts/03-s3-homework.sh`](scripts/03-s3-homework.sh) |
| Homework 2 - CLI report | [`scripts/04-cli-report.sh`](scripts/04-cli-report.sh) |
| Tear-down | [`scripts/99-cleanup.sh`](scripts/99-cleanup.sh) |
| Captured output | [`evidence/`](evidence/) - every command and its real result |

## How to run

```bash
cd lesson-28
./scripts/00-check-prereqs.sh     # does the CLI work, and as whom?
./scripts/01-iam-structure.sh     # run this one as root - it creates your IAM user
./scripts/02-budget-alert.sh
./scripts/03-s3-homework.sh
./scripts/04-cli-report.sh
```

Only script `01` needs the root account, and only because a fresh account has nobody else who could
create the first user. Everything after it runs on the `lesson-28` profile that `01` writes into
`~/.aws/credentials` - which is the actual point of the exercise.

```
        root  --------------->  01-iam-structure.sh
   (used once, then dropped)          |
                                      | creates
                                      v
              +----------------------------------------------+
              |  lesson28-admins      AdministratorAccess    | <-- admin.user
              |  lesson28-developers  lesson28-developer-... | <-- dev.user
              |  lesson28-readonly    ReadOnlyAccess         | <-- readonly.user
              +----------------------------------------------+
                        ^
                        | bgozlinski + access key + CLI profile "lesson-28"
                        |
        02 / 03 / 04  --+   (AWS_PROFILE=lesson-28, never root again)
```

Every script is idempotent - a second run reports `[skip]` and changes nothing:

```
=== Grupy ===
[skip] grupa lesson28-admins juz istnieje
[skip]   polityka juz podpieta do lesson28-admins
```

## Homework 1 - a complete AWS environment

### Organisational structure

Permissions go on **groups**, never directly on users. Changing somebody's role is then one
membership change instead of an audit of policies scattered across accounts.

| Group | Policy | Kind | User |
|---|---|---|---|
| `lesson28-admins` | `AdministratorAccess` | AWS managed | `admin.user`, `bgozlinski` |
| `lesson28-developers` | `lesson28-developer-policy` | customer managed | `dev.user` |
| `lesson28-readonly` | `ReadOnlyAccess` | AWS managed | `readonly.user` |

Two of the three are AWS managed policies - there is no reason to hand-write "read everything" when
Amazon maintains it for you. The developer one is custom, because that is where the real decisions
live ([`policies/developer-policy.json`](policies/developer-policy.json)):

| Statement | Effect |
|---|---|
| `ReadOnlyCompute` | `ec2:Describe*` and CloudWatch metrics - a developer may look at infrastructure |
| `ListAllBuckets` | can see that buckets exist |
| `FullAccessToLessonBucketsOnly` | full `s3:*`, but only on `arn:aws:s3:::lesson28-*` - blast radius limited by resource, not by trust |
| `ManageOwnCredentials` | may rotate keys and enrol MFA, scoped to `user/${aws:username}` - their own account only |
| `DenyEverythingWithoutMFA` | explicit `Deny` on everything except the calls needed to *set up* MFA, when `aws:MultiFactorAuthPresent` is false |

The last one is the interesting statement. An explicit `Deny` beats any `Allow`, so this developer
holds real permissions that simply do not exist in a session without MFA. `BoolIfExists` matters:
with a plain `Bool` the condition would not match requests that carry no MFA context at all, which
is exactly the case worth catching.

Every user and the policy carry `Environment=Learning` and `Lesson=28` tags, which is what lets the
tear-down script find them later.

Verification (`evidence/01-iam.txt`):

```
$ aws iam list-users --query Users[].UserName --output json
[
    "admin.user",
    "bgozlinski",
    "dev.user",
    "readonly.user"
]

$ aws iam list-groups-for-user --user-name dev.user --query Groups[].GroupName --output json
[
    "lesson28-developers"
]
```

### Stopping the use of root

`01-iam-structure.sh` finishes by creating `bgozlinski` in the admins group, calling
`iam create-access-key`, storing the answer in `.secrets/` (gitignored - AWS shows the secret
exactly once) and writing an AWS CLI profile from it:

```bash
aws configure set aws_access_key_id     "$AK_ID"      --profile lesson-28
aws configure set aws_secret_access_key "$AK_SECRET"  --profile lesson-28
aws configure set region                eu-central-1  --profile lesson-28
aws configure set output                json          --profile lesson-28
```

A brand new key is not usable immediately - IAM is eventually consistent, so the script retries
`sts get-caller-identity` for up to 25 seconds before it believes the key works. Then:

```
$ aws --profile lesson-28 sts get-caller-identity --output json
{
    "UserId": "AIDA2BRJDJEBZRDBV22CW",
    "Account": "690502191363",
    "Arn": "arn:aws:iam::690502191363:user/bgozlinski"
}
```

`arn:...:user/bgozlinski` instead of `arn:...:root` is the whole deliverable. Scripts 02-04 call
`use_lesson_profile`, which exports `AWS_PROFILE=lesson-28` unless something else is already set.

### Monitoring and alerting

One monthly cost budget, two notifications, both by email:

| Type | Threshold | Meaning |
|---|---|---|
| `ACTUAL` | > 80% of $10 | you have already spent $8 |
| `FORECASTED` | > 100% of $10 | at this rate you will pass $10 before the month ends |

The forecast alert is the one that matters. An actual-spend alert reports money that is already
gone; the forecast fires while there is still something to do about it.

```
$ aws budgets describe-notifications-for-budget --account-id 690502191363 \
      --budget-name lesson28-monthly-budget --output table
|| ComparisonOperator |  NotificationState  | NotificationType   | Threshold  ||
||  GREATER_THAN      |  OK                 |  ACTUAL            |  80.0      ||
||  GREATER_THAN      |  OK                 |  FORECASTED        |  100.0     ||
```

Budgets is a global service - the API answers in `us-east-1` regardless of the region configured in
the profile, so no `--region` is passed anywhere in `02-budget-alert.sh`.

## Homework 2 - AWS CLI

### 1. S3: create a bucket, upload, download

`03-s3-homework.sh` does the round-trip and verifies it with `diff`, so "it worked" is a check and
not a claim:

```
$ aws s3 ls s3://lesson28-bgozlinski-hw2/
40 test.txt

$ aws s3api head-object --bucket lesson28-bgozlinski-hw2 --key test.txt
{
    "Rozmiar": 40,
    "Typ": "text/plain",
    "Szyfrowanie": "AES256"
}

[ok]   pobrany plik jest identyczny z wgranym
```

(the listing and modification dates are trimmed here - the full output is in
`evidence/03-s3.txt`)

Bucket names are globally unique across all of AWS, so `head-bucket` runs before creating: a name
being taken can mean "mine already" or "somebody else's", and only the first is safe to carry on
with. Outside `us-east-1` the create call also needs an explicit `LocationConstraint`, which is a
classic first-day-in-AWS error.

Three settings are applied that AWS does not require but every real bucket wants: public access
blocked, AES256 server-side encryption, and the `Environment`/`Lesson` tags.

The task asks for the download to happen **through the web console**. That half is manual by
definition, so the script prints the link and leaves the clicking to you:

```
https://console.aws.amazon.com/s3/buckets/lesson28-bgozlinski-hw2?region=eu-central-1
select test.txt -> Download
```

### 2. Amazon Linux 2 AMIs

Amazon publishes hundreds of these, so the query sorts by date and keeps ten
(`evidence/04-cli-report.txt`):

```
$ aws ec2 describe-images --owners amazon \
      --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
      --query 'reverse(sort_by(Images, &CreationDate))[:10].[ImageId,Name,CreationDate]' \
      --output table
|  ami-01673e6aa92601eb5|  amzn2-ami-hvm-2.0.20260825.0-x86_64-gp2  |
|  ami-0c0c8fb359babd689|  amzn2-ami-hvm-2.0.20260817.0-x86_64-gp2  |
|  ami-018c83322e1f01c43|  amzn2-ami-hvm-2.0.20260803.1-x86_64-gp2  |
...
```

The image names carry their build date, so the sort order is still readable without the
`CreationDate` column; `evidence/04-cli-report.txt` has it in full.

The report also asks SSM Parameter Store for the same thing, because that is how automation should
do it - one call, no sorting, and the answer is always current:

```
$ aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2
[
    {
        "Parametr": "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2",
        "ImageId": "ami-01673e6aa92601eb5"
    }
]
```

Same AMI id as the top of the sorted list, which is the point.

### 3. Security groups

```
$ aws ec2 describe-security-groups --output table
|  Id   |  sg-07e0eed247f14826e         |
|  Nazwa|  default                      |
|  Opis |  default VPC security group   |
|  Vpc  |  vpc-0249521c72247d372        |
```

One group, the default that came with the default VPC. Its ingress rule allows protocol `-1`
(everything) but only from itself, not from `0.0.0.0/0` - the report prints the rules separately so
that distinction is visible rather than assumed.

### 4. IAM users and their details

For each of the four users the report collects account data and tags, group membership, directly
attached policies, inherited policies, and access keys:

```
$ aws iam list-attached-user-policies --user-name dev.user --query AttachedPolicies[].PolicyName
[]

$ inherited_policies dev.user
lesson28-developers: lesson28-developer-policy
```

The empty list is deliberate evidence, not a gap: no policy is attached to any user directly, so
every permission can only be arriving through group membership.

### 5. One service of my choice - VPC

VPC, because lesson 29 puts EC2 instances into it and it is worth knowing what is already there:

```
$ aws ec2 describe-vpcs --output table
|      Cidr      | Domyslna  |           Id            |   Stan     |
|  172.31.0.0/16 |  True     |  vpc-0249521c72247d372  |  available |

$ aws ec2 describe-subnets --output table
|  172.31.16.0/20|  subnet-02cd3501540803686  |  eu-central-1a |  4091    |
|  172.31.32.0/20|  subnet-0a302f86dfd76d0c4  |  eu-central-1b |  4091    |
|  172.31.0.0/20 |  subnet-0c296e41fe3ca3ea5  |  eu-central-1c |  4091    |
```

The default VPC has one subnet per availability zone, each with ~4091 free addresses. That is the
"high availability comes from availability zones" idea from the lesson, visible as three subnets in
three physically separate data centres.

## Evidence

Every `capture` call writes the command and its output to `evidence/`, so the quotes above are real
runs rather than transcription from the handout:

| File | Contents |
|---|---|
| `00-prereqs.txt` | CLI version, identity, availability zones |
| `01-iam.txt` | groups, users, memberships, identity on the new profile |
| `02-budget.txt` | budget definition, notifications, subscribers |
| `03-s3.txt` | upload, listing, object metadata, download |
| `04-cli-report.txt` | the whole of homework 2 |

Access key ids are masked (`AKIA************`) on the way into these files by `mask_secrets` in
`lib.sh`. The secret half never gets near them - it goes to `.secrets/`, which is gitignored.

## Security notes

| What this lesson does | What is still missing for production |
|---|---|
| root used once, then an IAM user | root MFA enabled and the root keys deleted entirely |
| long-lived access keys for the CLI | IAM Identity Center / `sts assume-role` with short-lived credentials |
| MFA enforced by policy for developers | MFA enforced for every group, admins included |
| `AdministratorAccess` on the admin group | permissions narrowed to what the role actually does |
| one account for everything | separate accounts per environment under Organizations |

`iam create-access-key` returns the secret exactly once and it is never retrievable again. If
`.secrets/` is lost, the fix is to delete the key and make a new one - there is nothing to recover.

## Common errors

| Symptom | Cause / fix |
|---|---|
| `InvalidClientTokenId` | key not yet propagated or deleted - `aws sts get-caller-identity`, check `~/.aws/credentials` |
| `Parameter validation failed: Invalid length for parameter PolicyArn` | a variable came out empty; in Git Bash `GROUPS` is a readonly builtin array, so the script uses `IAM_GROUPS` |
| `The user-provided path /c/... does not exist` | `aws.exe` does not understand Git Bash paths - `native_path()` converts them with `cygpath -w` |
| `IllegalLocationConstraintException` | bucket created outside `us-east-1` without `--create-bucket-configuration` |
| `EntityAlreadyExists` | the resource is already there - the scripts check first and print `[skip]` |
| `DeleteConflict` on `delete-user` | the user still has keys or group memberships - `99-cleanup.sh` removes those first |

## Clean up

IAM and Budgets cost nothing and the bucket holds 40 bytes, so leaving this in place is free. To
remove it anyway:

```bash
CONFIRM=yes ./scripts/99-cleanup.sh
```

The order is forced by AWS: object before bucket, keys and memberships before user, users before
group, policy detached everywhere before it can be deleted. The script also drops
`AWS_PROFILE=lesson-28` first - it is about to delete the very key it would otherwise be using.
