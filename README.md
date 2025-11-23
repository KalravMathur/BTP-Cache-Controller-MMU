# **End Term Project Report — RTL Cache Controller & MMU**

This branch contains the LaTeX source code and assets for the **End Term Report** of our B.Tech Minor Project.

---

## **Repository Contents**

- **`report.tex`** — Main LaTeX source file for the report.  
- **`logo.jpg`** — Source image used in report figures.

---

## **How to Compile the Report (Linux)**

To generate the PDF from the LaTeX source, ensure you have a TeX distribution installed.

---

## **1. Install Dependencies**

We only need a **minimal TeX Live installation** for compiling this report.

---

### **Minimal Installation**

```bash
sudo apt-get update

# Install base TeX Live and common packages
sudo apt-get install texlive-latex-base texlive-latex-extra texlive-fonts-recommended

# Install latexmk (automation tool)
sudo apt-get install latexmk
```

---

## **2. Clone the Repository & checkout endterm-report branch**

Clone the project and navigate into the directory:

```bash
git clone https://github.com/KalravMathur/BTP-Cache-Controller-MMU.git
cd BTP-Cache-Controller-MMU
git checkout endterm-report
```

---

## **3. Compile the PDF**

Use **latexmk** to automatically run all compilation steps.

```bash
latexmk -pdf report.tex
```

---

## **4. View the Report**

Once compilation is complete, open the generated `report.pdf`:

```bash
evince report.pdf &
```

Or open it in any PDF viewer.

---

## **5. Clean Up (Optional)**

To remove all auxiliary intermediate files (`.aux`, `.log`, `.toc`, etc.) and keep only the PDF:

```bash
latexmk -c
```

---
