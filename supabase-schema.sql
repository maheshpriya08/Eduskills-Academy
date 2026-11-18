-- EduSkills Academy database schema
-- Run this entire script in Supabase Dashboard → SQL Editor → New query.
create extension if not exists pgcrypto;

create table if not exists public.students (
 id uuid primary key default gen_random_uuid(),
 admission_no text unique,
 full_name text not null,
 date_of_birth date,
 parent_name text,
 parent_phone text,
 address text,
 class_name text,
 school_name text,
 subjects text,
 monthly_fee numeric(10,2) not null default 0 check(monthly_fee>=0),
 admission_date date not null default current_date,
 status text not null default 'Active' check(status in ('Active','Inactive')),
 created_at timestamptz not null default now()
);

create or replace function public.set_admission_no()
returns trigger language plpgsql as $$
declare next_no bigint;
begin
 if new.admission_no is null or new.admission_no = '' then
  perform pg_advisory_xact_lock(hashtext('eduskills_admission_' || extract(year from current_date)::text));
  select coalesce(max(nullif(regexp_replace(admission_no,'^EDA-'||extract(year from current_date)::text||'-',''),'')::bigint),0)+1
  into next_no from public.students
  where admission_no like 'EDA-'||extract(year from current_date)::text||'-%';
  new.admission_no := 'EDA-'||extract(year from current_date)::text||'-'||lpad(next_no::text,3,'0');
 end if;
 return new;
end $$;
drop trigger if exists students_admission_no on public.students;
create trigger students_admission_no before insert on public.students
for each row execute function public.set_admission_no();

create table if not exists public.payments (
 id uuid primary key default gen_random_uuid(),
 receipt_no text unique,
 student_id uuid not null references public.students(id) on delete restrict,
 fee_month text not null check(fee_month ~ '^[0-9]{4}-[0-9]{2}$'),
 amount numeric(10,2) not null check(amount>0),
 payment_date date not null default current_date,
 payment_method text not null default 'Cash',
 notes text,
 created_at timestamptz not null default now()
);
create sequence if not exists public.receipt_seq;
grant usage, select on sequence public.receipt_seq to authenticated;
create or replace function public.set_receipt_no()
returns trigger language plpgsql as $$
begin
 if new.receipt_no is null or new.receipt_no='' then
  new.receipt_no := 'EDA-R-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.receipt_seq')::text,5,'0');
 end if;
 return new;
end $$;
drop trigger if exists payments_receipt_no on public.payments;
create trigger payments_receipt_no before insert on public.payments
for each row execute function public.set_receipt_no();

create table if not exists public.attendance (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id) on delete restrict,
 attendance_date date not null,
 status text not null check(status in ('Present','Absent','Late')),
 created_at timestamptz not null default now(),
 unique(student_id,attendance_date)
);

-- Enable Row Level Security. This initial single-owner app allows authenticated users.
alter table public.students enable row level security;
alter table public.payments enable row level security;
alter table public.attendance enable row level security;

drop policy if exists "authenticated users manage students" on public.students;
create policy "authenticated users manage students" on public.students
for all to authenticated using (true) with check (true);
drop policy if exists "authenticated users manage payments" on public.payments;
create policy "authenticated users manage payments" on public.payments
for all to authenticated using (true) with check (true);
drop policy if exists "authenticated users manage attendance" on public.attendance;
create policy "authenticated users manage attendance" on public.attendance
for all to authenticated using (true) with check (true);

create index if not exists students_admission_no_idx on public.students(admission_no);
create index if not exists payments_student_month_idx on public.payments(student_id,fee_month);
create index if not exists attendance_date_idx on public.attendance(attendance_date);

-- Do not create a public/anon policy. Never expose the service_role key in the browser.
