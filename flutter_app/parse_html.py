import re
import html

class SimpleHTMLParser:
    def __init__(self, html_content):
        self.html = html_content
        
    def extract_text(self):
        # Remove script and style tags
        text = re.sub(r'<(script|style).*?>.*?</\1>', '', self.html, flags=re.IGNORECASE | re.DOTALL)
        # Remove SVG tags
        text = re.sub(r'<svg.*?>.*?</svg>', '', text, flags=re.IGNORECASE | re.DOTALL)
        # Extract plain text
        text = re.sub(r'<[^>]+>', ' \n', text)
        # Unescape HTML entities
        text = html.unescape(text)
        # Remove extra whitespace
        text = re.sub(r'\n\s*\n', '\n', text)
        return text

try:
    with open('C:/Users/rajta/Documents/python/final_rendered_design.html', 'r', encoding='utf-8') as f:
        content = f.read()
    
    parser = SimpleHTMLParser(content)
    text = parser.extract_text()
    
    with open('C:/Users/rajta/Documents/python/extracted_text.txt', 'w', encoding='utf-8') as f:
        f.write(text)
        
    print("Successfully extracted text to extracted_text.txt")
except Exception as e:
    print("Error:", e)
