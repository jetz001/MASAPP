# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/oee_logs/oee_log_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_code = """    await DbHelper.insert('machine_running_hours', {
      'hours_id': id,
      'machine_id': machineId,
      'cumulative_hours': hours,
      'target_production': target,
      'actual_production': actual,
      'good_production': good,
      'recorded_date': date.toIso8601String(),
      'data_source': dataSource,
    });"""

new_code = """    await DbHelper.execute(
      '''INSERT INTO machine_running_hours (
          hours_id, machine_id, cumulative_hours, target_production, actual_production, good_production, recorded_date, data_source
         ) VALUES (
          @id, @mId, @hrs, @tgt, @act, @good, @date, @src
         )''',
      params: {
        'id': id,
        'mId': machineId,
        'hrs': hours,
        'tgt': target,
        'act': actual,
        'good': good,
        'date': date.toIso8601String(),
        'src': dataSource,
      }
    );"""

content = content.replace(old_code, new_code)

with codecs.open('lib/features/oee_logs/oee_log_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed insert")
