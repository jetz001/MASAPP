import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_sql = """\"\"\"SELECT 
             as failure, 
            COUNT(*) as count
           FROM work_orders wo
           
           WHERE wo.status = 'completed' AND wo.created_at BETWEEN @start AND @end
           GROUP BY 
           ORDER BY count DESC
           LIMIT 15\"\"\""""

good_sql = """'''SELECT 
            $selectField as failure, 
            COUNT(*) as count
           FROM work_orders wo
           $joinClause
           WHERE wo.status = 'completed' AND wo.created_at BETWEEN @start AND @end
           GROUP BY $selectField
           ORDER BY count DESC
           LIMIT 15'''"""

content = content.replace(bad_sql, good_sql)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed SQL')
