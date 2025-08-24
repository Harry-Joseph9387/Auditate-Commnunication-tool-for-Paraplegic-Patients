# Audiate 🎙️
### Communication Device for Mute Paraplegic Individuals

This project, **Audiate**, is a hardware-software integrated assistive technology aimed at enabling communication for mute and paraplegic individuals.  
By leveraging sensors, microcontrollers, and AI-driven software, the system converts minimal muscle movements into text and speech, giving users a way to communicate effectively.

---

## 🚀 Features
- **Muscle-Movement Based Input**: Touch sensors detect voluntary movements from patients.  
- **Microcontroller Processing**: Signals are processed and transmitted via USB.  
- **AI-Powered Word Prediction**: Predicts and suggests words for faster communication.  
- **Text-to-Speech (TTS)**: Converts typed or predicted words into speech.  
- **Low-Cost & Accessible**: Designed using open-source hardware/software for affordability.  

---

## 📌 Problem Statement
Mute and paraplegic individuals face severe barriers in daily life due to limited communication methods. Traditional approaches (writing, sign language, eye movements) are inefficient or inaccessible in many situations.  
**Audiate provides an affordable, efficient, and universally understandable communication method.**

---

## 🎯 Objectives
- Develop a hardware-software system enabling effective communication.  
- Use open-source hardware/software (Arduino, ESP8266, Raspberry Pi, Flutter, etc.).  
- Build a **user-friendly, affordable, and replicable** system.  
- Improve independence and social inclusion for differently-abled individuals.  

---

## 🛠️ System Design
### Hardware Components
- **Touch Sensors**  
  - MPR121 Capacitive Touch Sensor (multi-touch, high sensitivity, low power)  
  - TTP223 Capacitive Touch Sensor Module (simple, reliable, low cost)  
- **Microcontroller Boards**  
  - NodeMCU ESP8266 (WiFi, GPIO support, affordable, strong community)  
  - Arduino Nano (compact, easy to program, robust support)  

### Software Components
- **Sensor Input Processing**  
- **AI-based Word Prediction** (trained on doctor-patient conversation corpus & other datasets)  
- **Text-to-Speech Conversion** (Flutter TTS and pretrained models)  
- **USB Communication** between hardware and software  

---

## 🔄 Workflow
1. Sensor detects voluntary muscle movements.  
2. Microcontroller interprets signals and sends them to software.  
3. Software processes input → predicts words.  
4. Predicted/typed words are converted to speech.  
5. Output is displayed on screen and spoken via speaker.  

---

## 📊 UML & Diagrams
- **Use Case Diagram**  
- **Data Flow Diagram**  
- **System Flow Diagram**  
- **Schematic Design**  

---

## 📅 Timeline
- **Week 1–2**: Problem identification & brainstorming  
- **Week 3–4**: Research on touch sensors  
- **Week 5–6**: Touch-based navigation system  
- **Week 7–8**: Implement text-to-speech functionality  
- **Week 9–10**: Testing, refinement, and documentation  

---

## 🔮 Future Enhancements
- Integration with **social media and entertainment platforms**.  
- Advanced AI for better word/phrase prediction.  
- Wireless connectivity for more portability.  

---

## ✅ Conclusion
Audiate enables mute paraplegic individuals to communicate efficiently, improving their independence and quality of life.  
By combining **cutting-edge technology** with **user-centric design**, the project offers a scalable and affordable solution for inclusive communication.

---

## 📚 References
- [Stephen Hawking’s Communication Device](https://www.scienceabc.com/innovation/stephen-hawking-cheek-communication-help-computer-speech-generating-device.html)  
- [Intel’s Voice for Stephen Hawking](https://www.wired.com/2015/01/intel-gave-stephen-hawking-voice/)  
- [IEEE Paper on Assistive Systems](https://ieeexplore.ieee.org/stamp/stamp.jsp?arnumber=9945963)  

---
