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
    parser.add_argument("--end-date", required=True, help="End date (YYYY-MM-DD).")
    return parser.parse_args()


def random_date(start_dt, end_dt):
    delta = end_dt - start_dt
    return start_dt + timedelta(seconds=random.randint(0, int(delta.total_seconds())))


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
        end_dt = datetime.strptime(args.end_date, "%Y-%m-%d").replace(
            hour=23, minute=59, second=59, tzinfo=timezone.utc
        )
    except ValueError as e:
        raise ValueError(f"Invalid date format. Use YYYY-MM-DD. Error: {e}")

    print(f"  Date Range:      {start_dt.strftime('%Y-%m-%d')} to {end_dt.strftime('%Y-%m-%d')}")
    print(f"  Random Seed:     42")

    print("\nConnecting to database...")
    
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        print("Fetching ads for the target client...")
        TARGET_CLIENT_ID = '35d69a44-9649-5556-81a0-251ab6dc537b'

        # 1. Fetch Client Config (For data-driven columns)
        cur.execute("""
            SELECT display_first_name_question_id, display_last_name_question_id, display_contact_question_id 
            FROM clients WHERE client_id = %s
        """, (TARGET_CLIENT_ID,))
        cfg = cur.fetchone()
        
        # NEW COLUMN NAMES
        first_qid = cfg['display_first_name_question_id'] if cfg else None
        last_qid = cfg['display_last_name_question_id'] if cfg else None
        email_qid = cfg['display_contact_question_id'] if cfg else None
        
        print(f"  Client Config: First Name Q_ID={first_qid}, Last Name Q_ID={last_qid}, Email Q_ID={email_qid}")

        # 2. Fetch Ads
        cur.execute("""
            SELECT a.ad_id, a.ad_name, a.reuse_ad_id, l.code AS language_code
            FROM ads a
            LEFT JOIN languages l ON l.language_id = a.language_id
            WHERE a.client_id = %s
            ORDER BY a.ad_name
        """, (TARGET_CLIENT_ID,))
        all_ads = cur.fetchall()

        if not all_ads:
            raise ValueError(f"No ads found for client {TARGET_CLIENT_ID}.")

        root_ads = [a for a in all_ads if a['reuse_ad_id'] is None]
        leaves   = [a for a in all_ads if a['reuse_ad_id'] is not None]

        if not root_ads:
            raise ValueError(f"No root ad found for client {TARGET_CLIENT_ID}.")

        root_ad = root_ads[0]
        print(f"  Root ad:  {root_ad['ad_name']} ({root_ad['ad_id']})")

        leaves_by_lang = {}
        for leaf in leaves:
            lang = leaf['language_code']
            if lang and lang not in leaves_by_lang:
                leaves_by_lang[lang] = leaf

        en_leaf = leaves_by_lang.get('en', root_ad)
        other_leaf_langs = sorted(lang for lang in leaves_by_lang if lang != 'en')

        # 3. Fetch FAQs
        cur.execute("""
            SELECT faq_id, question_id, question_order, question_type
            FROM faqs
            WHERE ad_id = %s
            ORDER BY question_order
        """, (root_ad['ad_id'],))
        faqs = cur.fetchall()
        print(f"\n  Root FAQs:              {len(faqs)}")

        # 4. Fetch qualification scores
        cur.execute("""
            SELECT qualification_score_id, level_code, score
            FROM qualification_score
            WHERE ad_id = %s
        """, (root_ad['ad_id'],))
        q_scores = cur.fetchall()
        print(f"  Root qualification bands: {len(q_scores)}")

        if not faqs or not q_scores:
            raise ValueError("Missing FAQs or Qualification Scores on the root ad.")

        all_question_orders = [f['question_order'] for f in faqs]
        abandon_points = all_question_orders[1:]

        first_names = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", "William", "Elizabeth"]
        last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"]
        domains = ["gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "icloud.com"]

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

        print("\nGenerating data (this may take a few seconds)...")

        customers_data = []
        conversations_data = []
        answers_data = []
        qualifications_data = []
        statuses_data = []

        for i in range(3000):
            if i > 0 and i % 1000 == 0:
                print(f"  ... generated {i} / 3000 conversations")

            target_ad = target_ads[i]
            target_ad_id = target_ad['ad_id']
            customer_id = i + 1 if i < 2000 else random.randint(1, 2000)

            if i < 2000:
                created_at = random_date(start_dt, end_dt)
                status = random.choices(
                    ['Pending', 'Contacted', 'Qualified', 'Converted', 'Withdrawn'],
                    weights=[10, 30, 40, 15, 5], k=1
                )[0]
                
                if status in ('Qualified', 'Converted'):
                    score = random.randint(60, 100)
                else:
                    score = random.randint(10, 50)
                    
                q_id = None
                for qs in q_scores:
                    if score >= qs['score'].lower and score < qs['score'].upper:
                        q_id = qs['qualification_score_id']
                        break
                if not q_id:
                    q_id = random.choice(q_scores)['qualification_score_id']

                customers_data.append((
                    customer_id, target_ad_id, None, 'chat',
                    f"user_{customer_id}", status, score, q_id, created_at
                ))

                note = random.choice([
                    "Customer requested pricing information.",
                    "Budget confirmation outstanding.",
                    "Decision-maker details provided.",
                    "Follow-up required regarding implementation timeline."
                ])
                statuses_data.append((customer_id, status, note, created_at))

            conv_type = conversation_types[i]
            conv_created_at = random_date(start_dt, end_dt)
            if i < 2000:
                conv_created_at = created_at + timedelta(minutes=random.randint(1, 60))

            if conv_type == 'completed':
                state = 'completed'
                current_order = max(all_question_orders) + 1
                completed_at = conv_created_at + timedelta(minutes=random.randint(2, 15))
            else:
                state = 'abandoned'
                current_order = random.choice(abandon_points)
                completed_at = None

            conversations_data.append((
                i + 1, customer_id, current_order, state, completed_at, conv_created_at
            ))

            for faq in faqs:
                faq_id = faq['faq_id']
                q_order = faq['question_order']
                q_type = faq['question_type']
                
                if q_order < current_order:
                    ans_text = None
                    ans_vals = None
                    
                    # Use the IDs from the database to correctly map answers
                    is_first = (first_qid and faq['question_id'] == first_qid) or (not first_qid and q_type == 'first_name')
                    is_last = (last_qid and faq['question_id'] == last_qid) or (not last_qid and q_type == 'last_name')
                    is_email = (email_qid and faq['question_id'] == email_qid) or (not email_qid and q_type == 'email_address')

                    if is_first:
                        ans_text = random.choice(first_names)
                    elif is_last:
                        ans_text = random.choice(last_names)
                    elif is_email:
                        fname = random.choice(first_names).lower()
                        lname = random.choice(last_names).lower()
                        rand_num = random.randint(1, 99)
                        ans_text = f"{fname}.{lname}{rand_num}@{random.choice(domains)}"
                    elif q_type in ('radio', 'dropdown_single'):
                        ans_text = "1"
                    elif q_type == 'dropdown_multi':
                        ans_vals = json.dumps(["1", "2"])
                    else:
                        ans_text = f"Sample answer for Q{q_order}"

                    answers_data.append((
                        i + 1, faq_id, ans_text, ans_vals,
                        conv_created_at + timedelta(seconds=q_order * 10)
                    ))

            if conv_type == 'completed':
                q_score_val = random.randint(60, 100)
                q_id = None
                for qs in q_scores:
                    if q_score_val >= qs['score'].lower and q_score_val < qs['score'].upper:
                        q_id = qs['qualification_score_id']
                        break
                if not q_id:
                    q_id = random.choice(q_scores)['qualification_score_id']

                qualifications_data.append((
                    i + 1, customer_id, root_ad['ad_id'],
                    q_score_val,
                    q_id,
                    completed_at, completed_at
                ))

        print("\nGeneration complete:")
        print(f"  Customers:       {len(customers_data)}")
        print(f"  Conversations:   {len(conversations_data)}")
        print(f"  Answers:         {len(answers_data)}")
        print(f"  Qualifications:  {len(qualifications_data)}")
        print(f"  Statuses:        {len(statuses_data)}")

        print("\nInserting data...")

        execute_values(cur, """
            INSERT INTO customers (
                customer_id, ad_id, demo_session_id, channel, channel_user_id,
                status, qualification_score, qualification_id, created_at
            )
            OVERRIDING SYSTEM VALUE
            VALUES %s ON CONFLICT DO NOTHING
        """, customers_data)

        execute_values(cur, """
            INSERT INTO conversations (
                conversation_id, customer_id, current_order, state,
                completed_at, created_at
            )
            OVERRIDING SYSTEM VALUE
            VALUES %s ON CONFLICT DO NOTHING
        """, conversations_data)

        execute_values(cur, """
            INSERT INTO answers (
                conversation_id, faq_id, answer_text, answer_values, created_at
            )
            VALUES %s ON CONFLICT DO NOTHING
        """, answers_data)

        execute_values(cur, """
            INSERT INTO qualifications (
                conversation_id, customer_id, ad_id, qualification_score,
                qualification_id, qualified_at, created_at
            )
            VALUES %s ON CONFLICT DO NOTHING
        """, qualifications_data)

        execute_values(cur, """
            INSERT INTO customer_statuses (
                customer_id, status, note, changed_at
            )
            VALUES %s ON CONFLICT DO NOTHING
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