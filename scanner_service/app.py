from flask import Flask, request, jsonify
from scanner.scan import scan_student_id

app = Flask(__name__)

@app.route('/scan', methods=['POST'])
def scan():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    
    file = request.files['file']
    
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    
    result = scan_student_id(file)
    
    return jsonify(result)

if __name__ == '__main__':
    app.run(debug=True)