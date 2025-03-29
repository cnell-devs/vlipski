import { useState } from "react";
import "./App.css";

function App() {
  const [formData, setFormData] = useState({
    videoUrl: "",
    email: "",
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState("");

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsSubmitting(true);
    setMessage("");

    try {
      // TODO: Replace with your actual API endpoint
      const response = await fetch(
        "https://ct3lqeom9h.execute-api.us-east-1.amazonaws.com/mypost",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(formData),
        }
      );

      if (!response.ok) {
        throw new Error("Failed to submit request");
      }

      setMessage("Success! We will send the video to your email shortly.");
      setFormData({ videoUrl: "", email: "" });
    } catch (error) {
      setMessage("Error: Please try again later.");
      console.error("Error submitting form:", error);
    } finally {
      setIsSubmitting(false);
      console.log(formData);

    }
  };

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: value,
    }));
  };

  return (
    <div className="container">
      <div className="form-wrapper">
        <h1>Video Downloader</h1>
        <p className="subtitle">
          Enter your video link and email to receive the download
        </p>

        <form onSubmit={handleSubmit} className="download-form">
          <div className="form-group">
            <label htmlFor="videoUrl">Video URL</label>
            <input
              type="url"
              id="videoUrl"
              name="videoUrl"
              value={formData.videoUrl}
              onChange={handleChange}
              placeholder="https://example.com/video"
              required
            />
          </div>

          <div className="form-group">
            <label htmlFor="email">Email Address</label>
            <input
              type="email"
              id="email"
              name="email"
              value={formData.email}
              onChange={handleChange}
              placeholder="your@email.com"
              required
            />
          </div>

          <button
            type="submit"
            className="submit-button"
            disabled={isSubmitting}
          >
            {isSubmitting ? "Processing..." : "Download Video"}
          </button>
        </form>

        {message && (
          <div
            className={`message ${
              message.includes("Error") ? "error" : "success"
            }`}
          >
            {message}
          </div>
        )}
      </div>
    </div>
  );
}

export default App;
