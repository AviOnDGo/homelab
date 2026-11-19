git -C ./ add .
git -C ./ commit -m "containerServices backup `date +'%d-%m-%Y %H:%M:%S'`"
git -C ./ push origin main
python ./notifier.py
