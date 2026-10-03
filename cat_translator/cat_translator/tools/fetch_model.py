#!/usr/bin/env python3
"""
빌드 시(GitHub Actions) 실행되는 스크립트.
공개된 사전학습 YAMNet TFLite 모델과 AudioSet 라벨 목록을 내려받아
Flutter 앱의 assets/models/ 폴더에 넣어준다.
(이 모델 파일은 저장소에 커밋하지 않고 빌드할 때마다 새로 받는다.)
"""
import csv
import io
import os
import sys
import urllib.request

ASSETS_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "models")
os.makedirs(ASSETS_DIR, exist_ok=True)

MODEL_URLS = [
    "https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/audio_classification/android/lite-model_yamnet_classification_tflite_1.tflite",
    "https://tfhub.dev/google/lite-model/yamnet/tflite/1?lite-format=tflite",
]
LABELS_URL = "https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv"


def download(url: str, dest: str) -> bool:
    try:
        print(f"[fetch_model] 다운로드 시도: {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        with open(dest, "wb") as f:
            f.write(data)
        print(f"[fetch_model] 성공: {dest} ({len(data)} bytes)")
        return True
    except Exception as e:  # noqa: BLE001
        print(f"[fetch_model] 실패: {url} -> {e}")
        return False


def main() -> int:
    model_dest = os.path.join(ASSETS_DIR, "yamnet.tflite")
    ok = False
    for url in MODEL_URLS:
        if download(url, model_dest):
            ok = True
            break
    if not ok:
        print("::error::YAMNet 모델을 어느 URL에서도 받지 못했습니다.")
        return 1

    labels_dest = os.path.join(ASSETS_DIR, "yamnet_labels.txt")
    try:
        req = urllib.request.Request(LABELS_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
        reader = csv.reader(io.StringIO(raw))
        rows = list(reader)
        header = rows[0]
        name_idx = header.index("display_name")
        labels = [row[name_idx] for row in rows[1:] if row]
        with open(labels_dest, "w", encoding="utf-8") as f:
            f.write("\n".join(labels) + "\n")
        print(f"[fetch_model] 라벨 {len(labels)}개 저장: {labels_dest}")
    except Exception as e:  # noqa: BLE001
        print(f"::error::라벨 목록을 받지 못했습니다 -> {e}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
