"""
tools/generate_demo_data.py
"""

import os
import random
import argparse
import json
from datetime import datetime, timezone, timedelta
import psycopg2
from psycopg2.extras import execute_values, RealDictCursor
from dotenv import load_dotenv


def parse_args():
    parser = argparse.ArgumentParser(description="Generate demo data for LeadWise AI.")
    parser.add_argument("--start-date", required=True, help="Start date (YYYY-MM-DD).")
    parser.add_argument("--end-date", help="End date (YYYY-MM-DD). Defaults to current time.")
    return parser.parse_args()


def random_date(start_dt, end_dt):
    delta = end_dt - start_dt
    return start_dt + timedelta(seconds=random.randint(0, int(delta.total_seconds())))


def get_business_hour_timestamp(start_dt, end_dt):
    """
    Returns a random timestamp. 
    95% between 7am and 7pm, 5% between 7pm and 7am.
    """
    max_day = min(end_dt, datetime.now(timezone.utc))
    day = random_date(start_dt, max_day).replace(hour=0, minute=0, second=0, microsecond=0)
    
    if random.random() < 0.95:
        hour = random.randint(7, 18)
    else:
        hour = random.choice([19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6])
        
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
        
    result = day.replace(hour=hour, minute=minute, second=second)
    
    if result > datetime.now(timezone.utc):
        result = datetime.now(timezone.utc) - timedelta(minutes=random.randint(1, 60))
        
    return result


def chunked_insert(cur, table_name, sql, data, chunk_size=1000):
    total = len(data)
    if total == 0:
        return
    for i in range(0, total, chunk_size):
        chunk = data[i:i + chunk_size]
        execute_values(cur, sql, chunk)
        print(f"      ... inserted {min(i + chunk_size, total)} / {total} into {table_name}")


def generate_data():
    args = parse_args()

    print("Loading environment variables...")
    load_dotenv(".env.website_demo")
    DATABASE_URL = os.getenv("WEBSITE_DEMO_DATABASE_URL")
    if not DATABASE_URL:
        raise ValueError("WEBSITE_DEMO_DATABASE_URL not found in .env.website_demo")

    safe_url = (
        DATABASE_URL.split('@')[0].split(':')[0] + ':***@' + DATABASE_URL.split('@')[1]
        if '@' in DATABASE_URL else "local"
    )
    print(f"  Target Database: {safe_url}")

    random.seed(42)

    try:
        start_dt = datetime.strptime(args.start_date, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        
        if args.end_date:
            end_dt = datetime.strptime(args.end_date, "%Y-%m-%d").replace(
                hour=23, minute=59, second=59, tzinfo=timezone.utc
            )
        else:
            end_dt = datetime.now(timezone.utc)
            
    except ValueError as e:
        raise ValueError(f"Invalid date format. Use YYYY-MM-DD. Error: {e}")

    print(f"  Date Range:      {start_dt.strftime('%Y-%m-%d')} to {end_dt.strftime('%Y-%m-%d %H:%M')}")
    print(f"  Random Seed:     42")

    print("\nConnecting to database...")
    
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        TARGET_CLIENT_ID = '35d69a44-9649-5556-81a0-251ab6dc537b'

        print("\n[1/8] Reading Client Config...")
        cur.execute("""
            SELECT display_first_name_question_id, display_last_name_question_id, 
                   display_phone_number_question_id, display_email_address_question_id 
            FROM clients WHERE client_id = %s
        """, (TARGET_CLIENT_ID,))
        cfg = cur.fetchone()
        
        first_qid = cfg['display_first_name_question_id'] if cfg else None
        last_qid = cfg['display_last_name_question_id'] if cfg else None
        phone_qid = cfg['display_phone_number_question_id'] if cfg else None
        email_qid = cfg['display_email_address_question_id'] if cfg else None
        print(f"      -> First: {first_qid}, Last: {last_qid}, Phone: {phone_qid}, Email: {email_qid}")

        print("\n[2/8] Reading Ads...")
        cur.execute("""
            SELECT a.ad_id, a.ad_name, a.reuse_ad_id, l.code AS language_code
            FROM ads a
            LEFT JOIN languages l ON l.language_id = a.language_id
            WHERE a.client_id = %s
            ORDER BY a.ad_name
        """, (TARGET_CLIENT_ID,))
        all_ads = cur.fetchall()

        root_ads = [a for a in all_ads if a['reuse_ad_id'] is None]
        leaves   = [a for a in all_ads if a['reuse_ad_id'] is not None]

        if not root_ads:
            raise ValueError(f"No root ad found for client {TARGET_CLIENT_ID}.")

        root_ad = root_ads[0]
        print(f"      -> Root Ad: {root_ad['ad_name']} ({root_ad['ad_id']})")

        leaves_by_lang = {}
        for leaf in leaves:
            lang = leaf['language_code']
            if lang and lang not in leaves_by_lang:
                leaves_by_lang[lang] = leaf

        en_leaf = leaves_by_lang.get('en', root_ad)
        other_leaf_langs = sorted(lang for lang in leaves_by_lang if lang != 'en')
        print(f"      -> Found {len(leaves)} leaf ads across {len(leaves_by_lang)} languages.")

        print("\n[3/8] Reading FAQs...")
        cur.execute("""
            SELECT faq_id, question_id, question_order, question_type, mandatory
            FROM faqs
            WHERE ad_id = %s
            ORDER BY question_order
        """, (root_ad['ad_id'],))
        faqs = cur.fetchall()
        print(f"      -> Found {len(faqs)} questions.")

        print("\n[4/8] Reading Qualification Scores...")
        cur.execute("""
            SELECT qualification_score_id, level_code, score
            FROM qualification_score
            WHERE ad_id = %s
        """, (root_ad['ad_id'],))
        q_scores = cur.fetchall()
        print(f"      -> Found {len(q_scores)} score bands.")

        if not faqs or not q_scores:
            raise ValueError("Missing FAQs or Qualification Scores on the root ad.")

        all_question_orders = [f['question_order'] for f in faqs]
        abandon_points = all_question_orders[1:]

        # Massive name pools for realistic diversity
        first_names = [
            "James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", "William", "Elizabeth",
            "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen",
            "Christopher", "Nancy", "Daniel", "Lisa", "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra",
            "Pieter", "Annelie", "Johan", "Elsa", "Daan", "Lize", "Francois", "Mariska", "Willem", "Riana",
            "Sipho", "Thabo", "Lerato", "Nomvula", "Sibusiso", "Nandi", "Mandla", "Palesa", "Bongani", "Zanele",
            "Teboho", "Kagiso", "Mpho", "Tshepo", "Nomsa", "Ayanda", "Lwazi", "Nhlanhla", "Khanyisile", "Sifiso"
        ]
        
        last_names = [
            "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
            "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
            "van der Merwe", "Botha", "Pretorius", "Coetzee", "du Plessis", "Nel", "Fourie", "Venter", "Kruger", "Steyn",
            "Ndlovu", "Mokoena", "Dlamini", "Nkosi", "Khumalo", "Mahlangu", "Zulu", "Nkomo", "Radebe", "Mofokeng",
            "Mabaso", "Sithole", "Msibi", "Ntuli", "Mthembu", "Ngcobo", "Zulu", "Maseko", "Shabalala", "Cele"
        ]

        business_names = [
            "Acme Corp", "Global Tech", "Cape Coffee Co", "Joburg Plumbing", "Sandton Legal",
            "Durban Design", "Pretoria Paints", "Soweto Eats", "Cape Town Cabs", "Kruger Safaris",
            "Blue Sky Media", "Nova Consulting", "Elite Auto", "Green Leaf Health", "Sunshine Retail",
            "Apex Logistics", "Vanguard Finance", "Pinnacle IT", "Summit Marketing", "Horizon Freight"
        ]

        # Email Domains
        domains = ["gmail.com"]*75 + ["yahoo.com"]*10 + ["mweb.com"]*5 + ["iafrica.com"]*10

        # SA Phone prefixes
        sa_mobile_prefixes = ["082", "083", "084", "060", "061", "062", "063", "064", "065", "066", "067", "068", "071", "072", "073", "074", "076", "078", "079", "081"]

        def get_random_name():
            return random.choice(first_names), random.choice(last_names)

        def get_random_phone():
            prefix = random.choice(sa_mobile_prefixes)
            return f"+27{prefix[1:]}{random.randint(1000000, 9999999)}"

        target_ads = []
        for _ in range(3000):
            if random.random() < 0.75:
                target_ads.append(en_leaf)
            else:
                if other_leaf_langs:
                    target_ads.append(leaves_by_lang[random.choice(other_leaf_langs)])
                else:
                    target_ads.append(en_leaf)

        conversation_types = ['abandoned'] * 750 + ['completed'] * 2250
        random.shuffle(conversation_types)

        print("\n[5/8] Generating in-memory data (3000 records)...")

        customers_data = []
        conversations_data = []
        answers_data = []
        qualifications_data = []
        statuses_data = []

        for i in range(3000):
            if i > 0 and i % 1000 == 0:
                print(f"      ... generated {i} / 3000")

            target_ad = target_ads[i]
            target_ad_id = target_ad['ad_id']
            
            customer_id = i + 1 if i < 2000 else random.randint(1, 2000)

            conv_type = conversation_types[i]
            
            conv_created_at = get_business_hour_timestamp(start_dt, end_dt)
            flow_duration_minutes = random.uniform(10, 20)
            
            if conv_type == 'completed':
                state = 'completed'
                current_order = max(all_question_orders) + 1
                completed_at = conv_created_at + timedelta(minutes=flow_duration_minutes)
            else:
                state = 'abandoned'
                current_order = random.choice(abandon_points)
                completed_at = None

            created_at = conv_created_at - timedelta(minutes=random.randint(1, 5))

            fname, lname = get_random_name()
            email_domain = random.choice(domains)
            email_addr = f"{fname.lower().replace(' ', '')}.{lname.lower().replace(' ', '')}{random.randint(1,99)}@{email_domain}"
            phone_num = get_random_phone()

            if conv_type == 'completed':
                status = random.choices(
                    ['Pending', 'Converted', 'Contacted', 'Withdrawn'],
                    weights=[10, 60, 25, 5], k=1
                )[0]
                
                # --- FIX: Pick a random qualification band, then a score within its range ---
                chosen_qs = random.choice(q_scores)
                min_score = chosen_qs['score'].lower
                max_score = chosen_qs['score'].upper - 1
                
                if max_score >= 211:
                    max_score = 210
                    
                q_score_val = random.randint(min_score, max_score)
                q_id = chosen_qs['qualification_score_id']
                    
            else:
                status = random.choices(
                    ['Not-Qualified', 'No-Response', 'Bad-Contact'],
                    weights=[50, 30, 20], k=1
                )[0]
                q_score_val = random.randint(0, 50)
                q_id = None 

            if i < 2000:
                customers_data.append((
                    customer_id, target_ad_id, None, 'chat',
                    f"user_{customer_id}", status, q_score_val, q_id, created_at
                ))

                statuses_data.append((customer_id, 'Pending', 'First contact', created_at))
                
                if conv_type == 'completed':
                    intermediate_pool = ['Contacted', 'Callback-Requested', 'No-Response', 'Bad-Contact', 'Duplicate', 'Qualified']
                    num_moves = random.randint(1, 3)
                    moves = random.choices(intermediate_pool, k=num_moves)
                    
                    if status not in moves:
                        moves.append(status)
                        
                    current_time = created_at
                    for move in moves:
                        current_time += timedelta(minutes=random.randint(5, 60))
                        note = random.choice([
                            "Called but no answer.",
                            "Customer requested pricing.",
                            "Follow-up scheduled.",
                            "Email sent.",
                            "Decision maker unavailable."
                        ])
                        statuses_data.append((customer_id, move, note, current_time))

            conversations_data.append((
                i + 1, customer_id, current_order, state, completed_at, conv_created_at
            ))

            for faq in faqs:
                faq_id = faq['faq_id']
                q_order = faq['question_order']
                q_type = faq['question_type']
                
                is_business_name = (q_type == 'business_name')
                
                if is_business_name and random.random() > 0.60:
                    continue
                
                if q_order < current_order:
                    ans_text = None
                    ans_vals = None
                    
                    is_first = (first_qid and faq['question_id'] == first_qid) or (not first_qid and q_type == 'first_name')
                    is_last = (last_qid and faq['question_id'] == last_qid) or (not last_qid and q_type == 'last_name')
                    is_phone = (phone_qid and faq['question_id'] == phone_qid) or (not phone_qid and q_type == 'phone_number')
                    is_email = (email_qid and faq['question_id'] == email_qid) or (not email_qid and q_type == 'email_address')

                    if is_first:
                        ans_text = fname
                    elif is_last:
                        ans_text = lname
                    elif is_business_name:
                        ans_text = random.choice(business_names)
                    elif is_phone:
                        ans_text = phone_num
                    elif is_email:
                        ans_text = email_addr
                    elif q_type == 'dropdown_multi':
                        num_choices = random.randint(2, 5)
                        chosen = random.sample(["1", "2", "3", "4", "5"], num_choices)
                        ans_vals = json.dumps(chosen)
                    elif q_type in ('radio', 'dropdown_single'):
                        ans_text = str(random.randint(1, 4))
                    else:
                        ans_text = f"Sample answer for Q{q_order}"

                    if current_order > 1:
                        time_offset = (q_order / current_order) * flow_duration_minutes
                    else:
                        time_offset = 0

                    answer_created_at = conv_created_at + timedelta(minutes=time_offset)

                    answers_data.append((
                        i + 1, faq_id, ans_text, ans_vals,
                        answer_created_at
                    ))

            if conv_type == 'completed':
                qualifications_data.append((
                    i + 1, customer_id, root_ad['ad_id'],
                    q_score_val,
                    q_id,
                    completed_at, completed_at
                ))

        print(f"      -> Generation complete.")

        print("\n[6/8] Inserting Customers and Conversations...")
        chunked_insert(cur, "customers", """
            INSERT INTO customers (
                customer_id, ad_id, demo_session_id, channel, channel_user_id,
                status, qualification_score, qualification_id, created_at
            ) OVERRIDING SYSTEM VALUE VALUES %s ON CONFLICT DO NOTHING
        """, customers_data)

        chunked_insert(cur, "conversations", """
            INSERT INTO conversations (
                conversation_id, customer_id, current_order, state,
                completed_at, created_at
            ) OVERRIDING SYSTEM VALUE VALUES %s ON CONFLICT DO NOTHING
        """, conversations_data)

        print("\n[7/8] Inserting Answers and Qualifications...")
        chunked_insert(cur, "answers", """
            INSERT INTO answers (
                conversation_id, faq_id, answer_text, answer_values, created_at
            ) VALUES %s ON CONFLICT DO NOTHING
        """, answers_data)

        chunked_insert(cur, "qualifications", """
            INSERT INTO qualifications (
                conversation_id, customer_id, ad_id, qualification_score,
                qualification_id, qualified_at, created_at
            ) VALUES %s ON CONFLICT DO NOTHING
        """, qualifications_data)

        print("\n[8/8] Inserting Customer Statuses...")
        chunked_insert(cur, "customer_statuses", """
            INSERT INTO customer_statuses (
                customer_id, status, note, changed_at
            ) VALUES %s ON CONFLICT DO NOTHING
        """, statuses_data)

        print("\nResetting sequences...")
        cur.execute("SELECT setval(pg_get_serial_sequence('customers', 'customer_id'), coalesce(max(customer_id), 1)) FROM customers;")
        cur.execute("SELECT setval(pg_get_serial_sequence('conversations', 'conversation_id'), coalesce(max(conversation_id), 1)) FROM conversations;")
        cur.execute("SELECT setval(pg_get_serial_sequence('answers', 'answer_id'), coalesce(max(answer_id), 1)) FROM answers;")
        cur.execute("SELECT setval(pg_get_serial_sequence('qualifications', 'qualification_event_id'), coalesce(max(qualification_event_id), 1)) FROM qualifications;")
        cur.execute("SELECT setval(pg_get_serial_sequence('customer_statuses', 'customer_status_id'), coalesce(max(customer_status_id), 1)) FROM customer_statuses;")
        
        conn.commit()
        print("\n✅ Successfully generated and inserted demo data!")

    except Exception as e:
        conn.rollback()
        print(f"\n❌ Error: {e}")
        print("Transaction rolled back. No data was inserted.")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    generate_data()