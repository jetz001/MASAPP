import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_downtime = "julianday(completed_at) - julianday(reported_at)"
good_downtime = "julianday(completed_at) - julianday(created_at)"
content = content.replace(bad_downtime, good_downtime)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed MTTR calculation in analytics_provider')
