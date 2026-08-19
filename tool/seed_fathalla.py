import urllib.request
import json
import subprocess

CITY_ALEXANDRIA = 'الإسكندرية'
CITY_GHARBIA = 'الغربية'
CITY_BEHEIRA = 'البحيرة'
CITY_CAIRO = 'القاهرة'
CITY_MATROUH = 'مطروح'
CITY_DAMIETTA = 'دمياط'
BEARER_PREFIX = 'Bearer '

def main():
    print("Getting gcloud access token...")
    token = subprocess.check_output(['gcloud', 'auth', 'print-access-token']).decode().strip()

    branches_data = [
        {'code': '209', 'name': 'طوسون', 'city': CITY_ALEXANDRIA, 'address': f'أبراج المستشارين، طوسون، {CITY_ALEXANDRIA}'},
        {'code': '210', 'name': 'النصر', 'city': CITY_ALEXANDRIA, 'address': f'شارع النصر، سموحة، {CITY_ALEXANDRIA}'},
        {'code': '211', 'name': 'سموحة', 'city': CITY_ALEXANDRIA, 'address': f'خلف مديرية الأمن، سموحة، {CITY_ALEXANDRIA}'},
        {'code': '212', 'name': 'جاردينيا', 'city': CITY_ALEXANDRIA, 'address': f'مدينة جاردينيا السيوف، {CITY_ALEXANDRIA}'},
        {'code': '213', 'name': 'فلمنج', 'city': CITY_ALEXANDRIA, 'address': f'شارع مصطفى كامل، فلمنج، {CITY_ALEXANDRIA}'},
        {'code': '214', 'name': 'الدخيلة ميني', 'city': CITY_ALEXANDRIA, 'address': f'الدخيلة، {CITY_ALEXANDRIA}'},
        {'code': '215', 'name': 'سيدي بشر ميني', 'city': CITY_ALEXANDRIA, 'address': f'35 ش الصاغ عبد السلام، سيدي بشر، {CITY_ALEXANDRIA}'},
        {'code': '216', 'name': 'الابراهيمية ميني', 'city': CITY_ALEXANDRIA, 'address': f'ش محمود حسن فهمي مع الكريم خطابي، الإبراهيمية، {CITY_ALEXANDRIA}'},
        {'code': '217', 'name': 'وصال', 'city': CITY_ALEXANDRIA, 'address': f'شارع مصطفى كامل / وصال، {CITY_ALEXANDRIA}'},
        {'code': '218', 'name': 'ستانلي', 'city': CITY_ALEXANDRIA, 'address': f'شارع عبد الحميد العبادي، ستانلي، {CITY_ALEXANDRIA}'},
        {'code': '219', 'name': 'الدخيلة ميني2', 'city': CITY_ALEXANDRIA, 'address': f'الدخيلة، {CITY_ALEXANDRIA}'},
        {'code': '220', 'name': 'ابو يوسف', 'city': CITY_ALEXANDRIA, 'address': f'أبو يوسف، العجمي، {CITY_ALEXANDRIA}'},
        {'code': '221', 'name': 'هانوفيل', 'city': CITY_ALEXANDRIA, 'address': f'شارع إسكندرية مطروح، الهانوفيل، العجمي، {CITY_ALEXANDRIA}'},
        {'code': '222', 'name': 'اكتوبر', 'city': CITY_ALEXANDRIA, 'address': f'محل رقم 1 بالعقار 27 ش جلال الدين سرى، أكتوبر النخيل، {CITY_ALEXANDRIA}'},
        {'code': '223', 'name': 'نيس', 'city': f'{CITY_ALEXANDRIA} / الساحل الشمالي', 'address': f'قرية نيس، الساحل الشمالي / {CITY_ALEXANDRIA}'},
        {'code': '224', 'name': 'عجمي ستار', 'city': CITY_ALEXANDRIA, 'address': f'مول العجمي ستار، العجمي، {CITY_ALEXANDRIA}'},
        {'code': '225', 'name': 'الابراهيمية', 'city': CITY_ALEXANDRIA, 'address': f'شارع زكي رجب، الإبراهيمية، {CITY_ALEXANDRIA}'},
        {'code': '226', 'name': 'سيدي جابر المحطة', 'city': CITY_ALEXANDRIA, 'address': f'مول محطة قطار سيدي جابر، {CITY_ALEXANDRIA}'},
        {'code': '227', 'name': 'الانفوشي', 'city': CITY_ALEXANDRIA, 'address': f'38 ش قصر التين، الجمرك، الأنفوشي، {CITY_ALEXANDRIA}'},
        {'code': '228', 'name': 'روزانا', 'city': f'{CITY_MATROUH} / الساحل الشمالي', 'address': f'قرية روزانا، الساحل الشمالي، {CITY_MATROUH}'},
        {'code': '231', 'name': 'طنطا', 'city': CITY_GHARBIA, 'address': f'شارع الجيش / النحاس، طنطا، {CITY_GHARBIA}'},
        {'code': '232', 'name': 'كفر الدوار', 'city': CITY_BEHEIRA, 'address': f'شارع الجيش، كفر الدوار، {CITY_BEHEIRA}'},
        {'code': '233', 'name': 'سيدي جابر ميني', 'city': CITY_ALEXANDRIA, 'address': f'خلف محطة سيدي جابر، {CITY_ALEXANDRIA}'},
        {'code': '234', 'name': 'مطروح', 'city': CITY_MATROUH, 'address': 'فندق سميراميس مطروح (نيو رويال سابقاً)، ش الكورنيش، مرسى مطروح'},
        {'code': '235', 'name': 'دمنهور الاندلس', 'city': CITY_BEHEIRA, 'address': f'ميدان الأندلس، دمنهور، {CITY_BEHEIRA}'},
        {'code': '240', 'name': 'سموحة ميني', 'city': CITY_ALEXANDRIA, 'address': f'شارع أدمون فريمون، سموحة، {CITY_ALEXANDRIA}'},
        {'code': '241', 'name': 'المحلة الكبري', 'city': CITY_GHARBIA, 'address': f'شارع شكري القوتلي، المحلة الكبرى، {CITY_GHARBIA}'},
        {'code': '242', 'name': 'أمواج', 'city': f'{CITY_MATROUH} / الساحل الشمالي', 'address': f'قرية أمواج، الساحل الشمالي، {CITY_MATROUH}'},
        {'code': '243', 'name': 'طنطا اوت ليت', 'city': CITY_GHARBIA, 'address': f'طريق طنطا الإسكندرية الزراعي، طنطا، {CITY_GHARBIA}'},
        {'code': '245', 'name': 'كفر الدوار مول', 'city': CITY_BEHEIRA, 'address': f'مول فتح الله، طريق مصر إسكندرية الزراعي، كفر الدوار، {CITY_BEHEIRA}'},
        {'code': '247', 'name': 'ملك حفني', 'city': CITY_ALEXANDRIA, 'address': f'شارع ملك حفني، سيدي بشر، {CITY_ALEXANDRIA}'},
        {'code': '248', 'name': 'سيتي سكوير', 'city': CITY_ALEXANDRIA, 'address': f'مول سيتي سكوير، سيدي جابر، {CITY_ALEXANDRIA}'},
        {'code': '250', 'name': 'مدينة الرحاب', 'city': CITY_CAIRO, 'address': f'السوق الشرقي، مدينة الرحاب، {CITY_CAIRO}'},
        {'code': '257', 'name': 'نيس2', 'city': f'{CITY_ALEXANDRIA} / الساحل الشمالي', 'address': f'قرية نيس 2، الساحل الشمالي / {CITY_ALEXANDRIA}'},
        {'code': '263', 'name': 'دمنهور الاستاد', 'city': CITY_BEHEIRA, 'address': f'شارع عبد السلام الشاذلي أمام الاستاد، دمنهور، {CITY_BEHEIRA}'},
        {'code': '268', 'name': 'دمياط الجديدة', 'city': CITY_DAMIETTA, 'address': f'المنطقة المركزية، دمياط الجديدة، {CITY_DAMIETTA}'},
        {'code': '272', 'name': 'بدر', 'city': CITY_CAIRO, 'address': f'الحي المتميز، مدينة بدر، {CITY_CAIRO}'}
    ]

    print(f"Uploading {len(branches_data)} Fathalla branches...")

    for i, b in enumerate(branches_data, 1):
        doc_id = f"fathalla_{b['code']}"
        url = f"https://firestore.googleapis.com/v1/projects/tashil-gift/databases/(default)/documents/branches/{doc_id}"
        
        body = {
            'fields': {
                'retailChainId': {'stringValue': 'fathalla'},
                'retailChainName': {'stringValue': 'أسواق فتح الله'},
                'branchName': {'stringValue': f"فرع {b['name']}"},
                'branchCode': {'stringValue': b['code']},
                'city': {'stringValue': b['city']},
                'address': {'stringValue': b['address']},
                'createdAt': {'timestampValue': '2026-08-18T12:00:00.000Z'},
                'receiptSignature': {
                    'mapValue': {
                        'fields': {
                            'storeId': {'stringValue': b['code']},
                            'posNumberPattern': {'stringValue': f"POS: {b['code']}"},
                            'receiptPattern': {'stringValue': f"{b['code']}/YYMMDD"},
                            'headerKeywords': {
                                'arrayValue': {
                                    'values': [
                                        {'stringValue': 'أسواق فتح الله'},
                                        {'stringValue': 'فتح الله'},
                                        {'stringValue': b['name']},
                                        {'stringValue': f"فرع {b['name']}"}
                                    ]
                                }
                            },
                            'footerKeywords': {
                                'arrayValue': {
                                    'values': [
                                        {'stringValue': 'شكراً لزيارتكم'},
                                        {'stringValue': 'أسواق فتح الله للجملة'}
                                    ]
                                }
                            },
                            'taxNumber': {'stringValue': '334-871-552'},
                            'commercialReg': {'stringValue': '124892'},
                            'hotline': {'stringValue': '15118'},
                            'confidenceScore': {'doubleValue': 1.0},
                            'extractedSummary': {'stringValue': f"فرع فتح الله ({b['name']}) - كود: {b['code']}، العنوان: {b['address']}"},
                            'sampleReceiptUrl': {'stringValue': ''},
                            'scannedAt': {'timestampValue': '2026-08-18T12:00:00.000Z'}
                        }
                    }
                }
            }
        }
        
        req = urllib.request.Request(
            url,
            data=json.dumps(body).encode('utf-8'),
            headers={'Authorization': BEARER_PREFIX + token, 'Content-Type': 'application/json'},
            method='PATCH'
        )
        try:
            with urllib.request.urlopen(req):
                print(f"[{i}/{len(branches_data)}] Success: {doc_id} - فرع {b['name']} (كود: {b['code']})")
        except Exception as e:
            print(f"[{i}/{len(branches_data)}] Error on {doc_id}: {e}")

    # Clean old duplicates
    old_ids = ['fathalla-fat-agm', 'fathalla-fat-hnf', 'fathalla-fat-kfr', 'fathalla-fat-smh']
    for old_id in old_ids:
        try:
            del_url = f"https://firestore.googleapis.com/v1/projects/tashil-gift/databases/(default)/documents/branches/{old_id}"
            del_req = urllib.request.Request(del_url, headers={'Authorization': BEARER_PREFIX + token}, method='DELETE')
            urllib.request.urlopen(del_req)
            print(f"Cleaned old duplicate: {old_id}")
        except Exception:
            pass

    # Update chain branches count
    try:
        chain_url = 'https://firestore.googleapis.com/v1/projects/tashil-gift/databases/(default)/documents/retail_chains/fathalla?updateMask.fieldPaths=branchesCount'
        chain_body = {
            'fields': {
                'branchesCount': {'integerValue': str(len(branches_data) + 6)}
            }
        }
        chain_req = urllib.request.Request(
            chain_url,
            data=json.dumps(chain_body).encode('utf-8'),
            headers={'Authorization': BEARER_PREFIX + token, 'Content-Type': 'application/json'},
            method='PATCH'
        )
        urllib.request.urlopen(chain_req)
        print("Updated retail_chains/fathalla branches count to", len(branches_data) + 6)
    except Exception as e:
        print("Error updating chain branches count:", e)

    print("ALL FATHALLA BRANCHES SEEDED SUCCESSFULLY!")

if __name__ == '__main__':
    main()

