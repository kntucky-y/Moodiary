# MBTI Methodology and References

This project uses an MBTI-style educational assessment for companion matching.
It is not the official licensed MBTI instrument.

## What We Implemented

- 30 self-report Likert items (1 to 5)
- Four dichotomies: E/I, S/N, T/F, J/P
- Deterministic scoring from item responses
- Deterministic MBTI-type to companion mapping
- Latest MBTI result stored on user profile
- Full MBTI attempt history stored per user

## Scoring Summary

- Each item contributes to one dichotomy.
- Reverse-keyed items are normalized with `6 - answer`.
- Scores are accumulated per pole (E, I, S, N, T, F, J, P).
- Type is derived by comparing each pole pair.

## References

1. Jung, C. G. (1921). *Psychological Types*.
2. Myers & Briggs Foundation. MBTI Basics:
   https://www.myersbriggs.org/my-mbti-personality-type/mbti-basics/
3. Pittenger, D. J. (2005). Cautionary comments regarding MBTI reliability and validity discussions.

## Important Note

This app does not claim clinical diagnosis, employment suitability, or psychological certification. It is a reflective matching tool for in-app companion suggestions.
