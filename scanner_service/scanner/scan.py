from flask import Flask, request, jsonify
import cv2
import numpy as np

app = Flask(__name__)

@app.route('/scan', methods=['POST'])
def scan_id():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    # Read the image file
    img = cv2.imdecode(np.fromstring(file.read(), np.uint8), cv2.IMREAD_COLOR)

    # Process the image to extract student ID (placeholder for actual scanning logic)
    # For example, you might use OCR here to read the ID
    scanned_text = "Sample Student ID"  # Replace with actual scanning logic

    return jsonify({'scanned_id': scanned_text})

if __name__ == '__main__':
    app.run(debug=True)