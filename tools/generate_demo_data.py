"""
tools/generate_demo_data.py

Generates 2,000 customers and 3,000 conversations (75% completed, 25% abandoned)
for the LeadWise AI demo dashboard. Sets demo_session_id to NULL for shared data.
"""

import os
import random
from datetime import datetime, timedelta, timezone
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

# 1. Setup
print("Loading environment variables...")
load_dotenv(".env.website_demo")
DATABASE_URL = os.getenv("WEBSITE_DEMO_DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("WEBSITE_DEMO_DATABASE_URL not found in .env.website_demo")

# Mask the password in the printout for security
safe_url = DATABASE_URL.split('@')[0].split(':')[0] + ':***@' + DATABASE_URL.split('@')[1] if '@' in DATABASE_URL else "local"
print(f"  Target Database: {safe_url}")

# Reproducible seed
random.seed(42)

START_DATE = datetime(2026, 1, 1, tzinfo=timezone.utc)
END_DATE = datetime.now(timezone.utc)
print(f"  Date Range:      {START_DATE.strftime('%Y-%m-%d')} to {END_DATE.strftime('%Y-%m-%d')}")
print(f"  Random Seed:     42")

def random_date():
    """Generate a random datetime between START_DATE and END_DATE."""
    delta = END_DATE - START_DATE
    random_seconds = random.randint(0, int(delta.total_seconds()))
    return START_DATE + timedelta(seconds=random_seconds)

def generate_data():
    print("\nConnecting to database...")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = False
    cur = conn.cursor()

    try:
        print("Fetching required foreign keys (Ads, FAQs, Q-Scores)...")
        
        # --- TARGET THE SPECIFIC CLIENT ---
        TARGET_CLIENT_ID = '35d69a44-9649-5556-81a0-251ab6dc537b'
        
        # Fetch Ad linked to this specific client
        cur.execute("SELECT ad_id, ad_name FROM ads WHERE client_id = %s LIMIT 1", (TARGET_CLIENT_ID,))
        row = cur.fetchone()
        if not row:
            raise ValueError(f"No ads found for client {TARGET_CLIENT_ID}. Please load the client JSON first.")
        ad_id, ad_name = row
        print(f"  Using Ad: {ad_name} ({ad_id}) for Client: {TARGET_CLIENT_ID}")

        # Fetch FAQs
        cur.execute("SELECT faq_id, question_order, question_text FROM faqs WHERE ad_id = %s ORDER BY question_order", (ad_id,))
        faqs = cur.fetchall()
        print(f"  Found {len(faqs)} FAQs for this ad.")
        
        # Fetch Qualification Scores
        cur.execute("SELECT qualification_score_id, level_code FROM qualification_score WHERE ad_id = %s", (ad_id,))
        q_scores = cur.fetchall()
        print(f"  Found {len(q_scores)} Qualification Score bands.")
        
        if not faqs or not q_scores:
            raise ValueError("Missing FAQs or Qualification Scores. Please ensure the base seed and client JSON are loaded first.")

        print("\nGenerating data (this may take a few seconds)...")
        
        customers_data = []
        conversations_data = []
        answers_data = []
        qualifications_data = []
        statuses_data = []

        # Ensure exactly 25% abandoned (750 abandoned, 2250 completed)
        conversation_types = ['abandoned'] * 750 + ['completed'] * 2250
        random.shuffle(conversation_types)

        for i in range(3000):
            # Print progress every 1000 iterations
            if i > 0 and i % 1000 == 0:
                print(f"  ... generated {i} / 3000 conversations")

            # 1. Customer (2000 unique, some have multiple conversations)
            customer_id = i + 1 if i < 2000 else random.randint(1, 2000)
            
            # Generate customer if it's a new ID
            if i < 2000:
                created_at = random_date()
                status = random.choices(
                    ['Pending', 'Contacted', 'Qualified', 'Converted', 'Withdrawn'],
                    weights=[10, 30, 40, 15, 5], k=1
                )[0]
                score = random.randint(10, 100)
                q_id = random.choice(q_scores)[0]
                
                customers_data.append((
                    customer_id, ad_id, None, 'chat', f"user_{customer_id}", 
                    status, score, q_id, created_at
                ))
                
                # Status history
                note = random.choice([
                    "Customer requested pricing information.",
                    "Budget confirmation outstanding.",
                    "Decision-maker details provided.",
                    "Follow-up required regarding implementation timeline."
                ])
                statuses_data.append((customer_id, status, note, created_at))

            # 2. Conversation
            conv_type = conversation_types[i]
            conv_created_at = random_date()
            
            # Ensure conversation is after customer creation
            if i < 2000:
                conv_created_at = created_at + timedelta(minutes=random.randint(1, 60))

            if conv_type == 'completed':
                state = 'completed'
                current_order = len(faqs)
                completed_at = conv_created_at + timedelta(minutes=random.randint(2, 15))
            else:
                state = 'abandoned'
                current_order = random.randint(1, len(faqs) - 1)
                completed_at = None

            conversations_data.append((
                i + 1, customer_id, current_order, state, completed_at, conv_created_at
            ))

            # 3. Answers (Simulate partial or full completion)
            for faq in faqs:
                faq_id, q_order, _ = faq
                if q_order <= current_order:
                    answers_data.append((
                        i + 1, faq_id, f"Sample answer for Q{q_order}", None, conv_created_at + timedelta(seconds=q_order*10)
                    ))

            # 4. Qualifications (Only if completed)
            if conv_type == 'completed':
                qualifications_data.append((
                    i + 1, customer_id, ad_id, random.randint(10, 100), 
                    random.choice(q_scores)[0], completed_at, completed_at
                ))

        print("\nGeneration complete. Summary of generated records:")
        print(f"  Customers:       {len(customers_data)}")
        print(f"  Conversations:   {len(conversations_data)} (750 abandoned, 2250 completed)")
        print(f"  Answers:         {len(answers_data)}")
        print(f"  Qualifications:  {len(qualifications_data)}")
        print(f"  Statuses:        {len(statuses_data)}")

        # --- BULK INSERT ---
        print("\nInserting data into database...")
        
        print("  Inserting Customers...")
        execute_values(cur, """
            INSERT INTO customers (customer_id, ad_id, demo_session_id, channel, channel_user_id, status, qualification_score, qualification_id, created_at)
            OVERRIDING SYSTEM VALUE
            VALUES %s ON CONFLICT DO NOTHING
        """, customers_data)

        print("  Inserting Conversations...")
        execute_values(cur, """
            INSERT INTO conversations (conversation_id, customer_id, current_order, state, completed_at, created_at)
            OVERRIDING SYSTEM VALUE
            VALUES %s ON CONFLICT DO NOTHING
        """, conversations_data)

        print("  Inserting Answers...")
        execute_values(cur, """
            INSERT INTO answers (conversation_id, faq_id, answer_text, answer_values, created_at)
            VALUES %s ON CONFLICT DO NOTHING
        """, answers_data)

        print("  Inserting Qualifications...")
        execute_values(cur, """
            INSERT INTO qualifications (conversation_id, customer_id, ad_id, qualification_score, qualification_id, qualified_at, created_at)
            VALUES %s ON CONFLICT DO NOTHING
        """, qualifications_data)

        print("  Inserting Statuses...")
        execute_values(cur, """
            INSERT INTO customer_statuses (customer_id, status, note, changed_at)
            VALUES %s ON CONFLICT DO NOTHING
        """, statuses_data)

        # --- FIX SEQUENCES ---
        print("\nResetting auto-increment sequences (preventing live data collisions)...")
        
        cur.execute("SELECT setval(pg_get_serial_sequence('customers', 'customer_id'), coalesce(max(customer_id), 1)) FROM customers;")
        print("  -> Customers sequence reset.")
        
        cur.execute("SELECT setval(pg_get_serial_sequence('conversations', 'conversation_id'), coalesce(max(conversation_id), 1)) FROM conversations;")
        print("  -> Conversations sequence reset.")
        
        cur.execute("SELECT setval(pg_get_serial_sequence('answers', 'answer_id'), coalesce(max(answer_id), 1)) FROM answers;")
        print("  -> Answers sequence reset.")
        
        cur.execute("SELECT setval(pg_get_serial_sequence('qualifications', 'qualification_event_id'), coalesce(max(qualification_event_id), 1)) FROM qualifications;")
        print("  -> Qualifications sequence reset.")
        
        cur.execute("SELECT setval(pg_get_serial_sequence('customer_statuses', 'customer_status_id'), coalesce(max(customer_status_id), 1)) FROM customer_statuses;")
        print("  -> Customer Statuses sequence reset.")

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