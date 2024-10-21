function display_logs() {
  if [ $# -eq 2 ] && [ "$1" = "logs" ]; then
    case "$2" in
      app)
        docker logs --follow app
        ;;
      job)
        docker logs --follow job
        ;;
      db)
        docker logs --follow postgres
        ;;
      *)
        echo "Please specify a valid log type: app, job, or db"
        exit 1
        ;;
    esac
  else
    echo "Usage: $0 logs <app|job|db>"
    exit 1
  fi
}
