-- Seed only the public product catalog for Staging; no orders or user subscription states.

insert into public.monetization_plans
(code,name,price_rub,period_days,active_listing_limit,features,is_active,sort_order)
values
('free','Free',0,null,3,'["До 3 активных объявлений","Чат и предложения обмена","Обмен без комиссии платформы"]'::jsonb,true,10),
('pro','PRO',299,30,20,'["До 20 активных объявлений","Расширенные фильтры","Уведомления о совпадениях"]'::jsonb,true,20),
('pro_plus','PRO+',599,30,100,'["До 100 активных объявлений","Статистика просмотров за 7 и 30 дней","1 поднятие, 1 выделение и 1 VIP-размещение в месяц"]'::jsonb,true,30),
('business','Business',1490,30,500,'["До 500 активных объявлений","Командный доступ для 5 участников","Расширенная аналитика просмотров"]'::jsonb,true,40),
('boost_24h','Поднять объявление',99,1,1,'["Поднятие в выдаче на 24 часа"]'::jsonb,true,50),
('highlight_7d','Выделение объявления',149,7,1,'["Выделение объявления на 7 дней"]'::jsonb,true,60),
('vip_7d','VIP-размещение',299,7,1,'["VIP-размещение на 7 дней"]'::jsonb,true,70)
on conflict (code) do update set
 name=excluded.name,price_rub=excluded.price_rub,period_days=excluded.period_days,
 active_listing_limit=excluded.active_listing_limit,features=excluded.features,
 is_active=excluded.is_active,sort_order=excluded.sort_order;
