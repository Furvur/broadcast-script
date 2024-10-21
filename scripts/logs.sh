function display_logs() {
  if [ $# -eq 2 ] && [ "$1" = "logs" ]; then
    case "$2" in
      app)
        docker logs app
        ;;
      job)
        docker logs job
        ;;
      db)
        docker logs postgres
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
